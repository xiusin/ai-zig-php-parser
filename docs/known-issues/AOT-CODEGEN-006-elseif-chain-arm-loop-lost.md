# elseif 链臂内含循环：末臂整块丢失 / 臂间互斥性丧失串臂 / 函数上下文跑错臂

**问题 ID**: AOT-CODEGEN-006
**优先级**: P0（**静默语义破坏**：编译成功、退出码 0、无任何报错，输出与 PHP 不一致；其中「三臂顺序全执行」直接破坏 if/elseif/else 互斥语义。语料 68 脚本全绿但对该形状 **0 覆盖**）
**状态**: **A 批 + D 批 + R9-B 批已落地并全门实测绿，并已与 RC-5 批**按老铁「四批合一提交」**于 2026-10-05 入库 = `497edc6`**（27 文件 `+4028/−93`：`native_linker.zig` vs 旧 HEAD `+385/−30` + 四批工单/变更文档 + 冻结基线 `baseline_main_zig_md5.tsv` + 13 个门脚本 ⇒ **task #63 闭环**；代次链 `3ae7b34e` → `22a217f0` → `9490bf9f` → `0e38b018`） —— 取证闭环：IR 层 + 发射层 + trace 两轮（R1/R2）+ 还原复验（R3）+ 影子实测三轮（R4 88 脚本 / R5 96 / R6 114）。修复闭环：**A 类**（四处臂尾 `.br` 窄四前缀循环头派发，§4.2）⇒ 形 1/5/6 转绿 + PERF-001 mode=1 兑现；**D 类**（`chain_unwind` 裸 break 改双臂发射，§4.3）⇒ 形 8 转绿；**R9-B 类**（`.cond_br` 选路处就地求链 IPD 结构 merge，§3.14 + §4.5）⇒ 形 4 转绿。九形门现读 `total=9 same=7 differs=2`（红 = 形 7/9；`same=6` 为 D 批代次登记值，保留不改写），D 旁门 `total=2 same=2`；**硬零漂移 `diff=0`** + 官方 68 `PASS 67 / SKIP 1` + 巡检 `mismatch=0` + 抽查 `ok=5` + `zig build test 21/21 & 326/326`。**旧口径两处作废**（留档于此防复用）：① 本行曾写「发射侧仍一行未改」；② 曾认为「区间以兄弟臂为界」口径完备 —— 该判据已被 **R5 的 `inh=0` 与 R6 的 12 事件红绿不可分**逐条否证（§3.6.4 / §3.7），本批只在**显式双臂形态内部**用兄弟臂块作该臂自身帧界，不构成泛化区间规则。**未闭合**：余形 7/9（B/C 类）**六轮同层判据已搜索穷尽并逐轮否证**（R5 区间/上界 → R6 臂归属 → R7 臂重联 → R8/R8.1 terminator + 计数 → R10 选路站点静态字段（§3.15，第五次）→ **R11 结构帧界（CFG 可达性 ⊖ IPD ⊖ 兄弟臂，§3.16，第六次）**，六轮均 `drift_diff=0` 零行为插桩实测）⇒ 硬要求「语料命中面 = 0」在任何**发射前静态判据**上无法满足；**R11 另给出两条正向实测**：`arms` 截止集对帧界零增益（`teA==teB` 35/35）⇒ §7 路线 ①②′ 已被排除为充分机制；绿事件 **7/7 满足 `lfi == 链 IPD`** ⇒ 判别性只在**帧收口回传侧** ⇒ **唯一剩余路线 = §7 路线 ③（帧收口站点回传：`lfi==null ∧ m` 存在时以 `m` 为回传目标）**，任务 **#72** 结案、待老铁点头后才动编译器源码。**R12（#75，2026-10-05）已把该路线定面完成**：`+105/−0` 只读探针、中性双证绿（九形 `same=7` 同判 + 全量 `drift_diff=0`），实测得 **T1 侧「判据成立 ∧ 语料命中面 = 0 事件」= 七轮来第一条可落地判据**（形 9 命中，候选节点必须是 `ei` 而非帧起点；静态 IPD 与动态回落 14 事件仅 1 条等值 ⇒ 只准加 `lfi==null` 兜底支、禁止替换）；**T3 侧判据不落地**（T3-PRE/POST 两侧合计 96 条语料读数五条件真 0，且形 7 在该站点 `m=NONE`）⇒ **余形由 2 形压缩为「形 7 单形」**，其排除理由从「判据不可二分」改记为「机制前置条件不成立」。落地批（T1 单站点 `else if` 兜底）已按老铁授权**编码、建代次、实测并撤销**（§3.18，2026-10-05）⇒ **第八次否证，性质与前三次不同**：判据**触发面完全正确**（形 9 三行读数全真、其余 8 形 0 触发、语料 0 触发，与 R12 定面逐字吻合），但**动作惰性** —— 落地批与提交代次两份形 9 `main.zig` 仅差 1 行注释、AOT 输出逐字未变，九形门仍 `same=7 differs=2` ⇒ 预测 `same=8` 被否证。**机理 = 结构性死锁**：`then_end` 在递归行走**之前**由 `:8837–:8854` 定为 `end_idx`（兄弟臂 5..8 已在帧内线性发射），而 `last_loop_fallthrough_idx` 只有行走**之后**才可知 ⇒ 以 `lfi==null` 为前置的事后交还在原理上修不了形 9。⇒ 形 9/7 的唯一在途路线 = **路线 ③ 的完整形态**（`generateLabelDrivenBlockRange` 返回「帧停止块」回传调用层；实测波及调用站点 **94 处**）或**新机制**；工作区已回到 HEAD `497edc6`（`0e38b018`/32796，`git status` 干净），待裁决项见 §7。**2026-10-05/06 追加（状态行现行末尾）**：**R14（#79）= 第九次否证**（foreach 停走口径外扩到 for/while：红形 0 读数 + 唯一反事实读数落在冻结通过脚本 `f124`；`[R14-FORX]` 把阻塞物从「消费点晚于行走」改判为「**for 侧记录器缺失**」，§3.19）⇒ **R15（#80）= 本族十轮以来首次「非否证」**（`HOPQ` 判据 150 事件里唯一命中红形 9、绿形 0、**语料面 0**，且语料两条 `defer=1` 均被更靠前的 `:14923` 接走 ⇒ 新支结构不可达；§3.20）⇒ **§4.7 成对候选（for 侧一跳纯记录支 + foreach/for 共用帧内停走）进入落地评审，模板与标识符均已实文复验，等老铁「落地」**，验收目标 `same=8 differs=1`。**R16（#83）零插桩复证形 7** ⇒ 本单 §3.10 对形 7 的诊断被推翻：其二级 `cond_br` 终止符从未派发、末臂子树整体未发射、且该链**没有 `if_merge_` 块**（13 探针普查唯一）⇒ `merge_bi`/IPD/`defer`/`lfi` 对形 7 **原理上无对象** ⇒ 形 7 由 C 类**改判 A/D 类**，§4.7 候选永不覆盖它；其唯一合法前置 = **R17（#84，待点头）**，见 §3.21；**R17 原口径（「五枚内联发射站点中谁吞掉了它」）已由 §3.21.1 交叉复算作废** —— 吞掉者在 R8 读数中即定位（`nested_then_idx` 兜底线性摊平 + 块 3 的 `ret` 冒泡触发 `markReachableRestBlocks`），R17 现收窄为**单枚 `ttag` 面探针轮**（站点 = `S09N`，语料面未知；**其开轮前置已由 §3.21.2 只读实文核对完成** ⇒ 站点行号实测 `:10178/:10179/:10197/:10202/:10214`、blame 实证未迁移，点头后可直接插桩）。**§3.22（#86，2026-10-06）对 #81 落地批的只读复验**：锚点与模板标识符在当前代次**全部等值**（含 `:14975↔:14977` 插入界、`:7471–:7477` 抄写模板、`:7482–:7485` 缺 `loop_head_idx` 的 +2 行、helper 缝 `:7429/:7431`、消费侧 `:8865/:8884`），另得三条口径 —— ① 坑 3 的排除面（`isLoopHeadLabel` 九枚）**严格宽于** `.br` 派发支自用五枚 ⇒ 不得收窄，收窄即双写 `lfi`；② 改动二覆盖面 = `generateForFromLabels` 九个派发返回点中的 **1 个**（`:7483`），八处弃返回值站点的风险由 §3.20「语料面 0」封闭；③ **阻断项**：改动二按现稿谓词逐字落地会重触发 R14 实测的 `f124` 停走（`lfi=3=i`、`lh=4` ⇒ `stop=1`，「成对」只消解了 R14 第 ① 半），该批必挂在自家硬零漂移门上 ⇒ **「落地」点头的前置改为先裁决 §3.22.3 的窄化口径 N1（`lfi ≠ 派发返回值`，推荐）或 N2（新鲜度标记）**。顺带：`@NNNN` 形锚点不在 #74 的 `:NNNN` 清洗面内，实测 3 处中 `@7702` 已失效（真实置位点 `:7841`，偏 139 行），登记为 #74 未提交批的候选追加行、**本轮未改源码**；`ttag` 语料面经留存物普查确认**不可零插桩回收**（全仓 `*.log` 命中 0）⇒ R17 仍是唯一路径。**当前工作区代次 = #74 纯注释锚点批 `fbe6382a…`/32797（`git diff --numstat` = `5 4`，发射中性由硬零漂移实证），未提交。**
**发现日期**: 2026-10-04（由 AOT-PERF-001 热点探针 `perf001_hotspot_probe_tmp.php` 的 mode=1 空输出逆向暴露 ⇒ 立项时该性能读数作废；**A 批落地后 mode=1 已正常执行并逐字节等值 ⇒ 读数恢复有效**，H1 ≈166 ns/迭代，见 §6 到期兑现）
**关联**: [AOT-CODEGEN-005](AOT-CODEGEN-005-foreach-body-if-arms-lost.md)（同族：RC-2「臂内嵌 for 塌缩为仅初始化」/ RC-4「臂尾裸 break-continue 被折进内层循环出口」/ RC-5「臂尾 latch 交还」——**本工单站点是 if/elseif 链自身，不是循环体臂**）；历史 #14「f007 缺陷2：循环内 elseif/else 臂丢失」（互为镜像：#14 是循环在外 elseif 在内，本单是 elseif 在外循环在内）

---

## 1. 复现（永久探针，勿删）

门：`bash fuzzy_scripts_720/tmp/c006_tl_probe_run_tmp.sh`（9 形逐字节等值，档位 `--optimize=release-fast`；用 `AOT_BIN=<path>` 可换二进制复跑同一门）。

| # | 探针 | 几何 | PHP 真值 | AOT 实际 | 症状类 |
|---|---|---|---|---|---|
| 1 | `c006_tl_shape1_tmp.php` | 顶层 if/elseif/else，**else 臂含 for** | `T1 hit=3 sum=3` | **空输出** | 末臂整块丢失 |
| 2 | `c006_tl_ifelse_loop_tmp.php` | 顶层 if/else（**无 elseif**），else 臂含 for | `T2 hit=3` | 等值 | 绿（对照） |
| 3 | `c006_tl_else_echo_tmp.php` | 顶层 if/elseif/else，else 臂**只有 echo** | `T3 else` | 等值 | 绿（对照） |
| 4 | `c006_tl_elseif_loop_tmp.php` | for 在 **elseif 臂** | `T4 hit=3 sum=3` | `T4 else` + `T4 hit=3 sum=3`（**两臂串跑**） | 互斥性丧失 |
| 5 | `c006_tl_else_while_tmp.php` | else 臂含 **while** | `T5 hit=3 sum=3` | 空输出 | 末臂丢失（循环类型无关） |
| 6 | `c006_tl_else_loop_tail_tmp.php` | 形状1 + 链后一条顶层尾语句 | `T6 hit=3 sum=3` + `T6 tail` | 仅 `T6 tail` | 臂丢、链尾存活 |
| 7 | `c006_tl_fncontext_loop_tmp.php` | 同形状1 几何**放进函数体**（return 代替 echo） | `T7 hit=3 sum=3` | `T7 branch3`（**跑错臂**） | 非顶层专属 |
| 8 | `c006_tl_two_elseif_loop_tmp.php` | 两级 elseif + 末 else 含 for | `T8 hit=3 sum=3` | 空输出 | 链长度放大 |
| 9 | `c006_tl_ifarm_loop_tmp.php` | for 在**首个 if 臂** | `T9 hit=3 sum=3` | `T9 hit=3 sum=3` + `T9 b2` + `T9 else`（**三臂顺序全执行**） | 互斥性丧失（最危险） |

门读数（2026-10-04）：`C006_TL_GATE_DONE total=9 same=2 differs=7`。

**档位无关**（同两颗二进制、两种档位实测）：形状1/9 在项目默认档（不加 `--optimize`，即 `release_small`）下输出与 `release-fast` 逐字节相同 ⇒ 非优化档位问题。

**HEAD 对照（关键：不是 RC-5 批次引入的回归）**：

| 项 | 工作区（RC-5 facet-1+facet-2 未提交，blob `3ae7b34e`） | HEAD `0ff09cf`（worktree `/tmp/parser_head_wf` 独立构建） |
|---|---|---|
| 门判定 | `same=2 differs=7` | `same=2 differs=7`（`SAME_CLASSIFICATION`） |
| AOT 侧输出载荷 | — | `AOT_OUTPUT_IDENTICAL_ACROSS_BINARIES`（7 个红形的 `aot=[...]` 串逐字节相同） |

⇒ **既有缺陷**，与待提交的 RC-5 批次零耦合；「是否提交 RC-5」的决策不因本单改变，但本单是提交后**第一个新 P0**。

### 1.1 D 批新增两条取臂面探针（永久，勿删；2026-10-04 立）

9 形门对形 8 只覆盖了「末 **else** 臂（含循环）被取用」这一条路径；D 批把 `chain_unwind` 的裸 break 改成**双臂发射**后，`then` 侧与链首臂从未被门覆盖 ⇒ 用同几何、只改 `$mode` 取值补两形（IR 结构与形 8 完全相同，运行时取臂不同）。

| # | 探针 | 取臂 | PHP 真值（`/opt/homebrew/bin/php` 实测） | 本门要否证的假设 |
|---|---|---|---|---|
| D-1 | `c006_tl_two_elseif_then_tmp.php` | 末节点 **then 臂**（`$mode==="4"`） | `T10 b4` | 双臂发射后 `then` 臂**落入** `else` 臂体（若成立输出会变两行：`T10 b4` + `T10 hit=3 sum=3`） |
| D-2 | `c006_tl_two_elseif_early_tmp.php` | 链**首臂**（`$mode==="2"`） | `T11 b2` | 首臂尾部接成 fallthrough，串跑到含循环的末臂 |

门：`bash fuzzy_scripts_720/tmp/c006_d_probe_run_tmp.sh` ⇒ `C006_D_GATE_DONE total=2 same=2 differs=0`（档位 `--optimize=release-fast`，支持 `AOT_BIN=` 换二进制）。

**禁止并入 9 形门**：`total=9` 与 `same=5/6` 的分级读数已写入 §3.5/§3.6/§4.2 的验收记录，追溯性改写会让历史批次判定失真（与 do-while 门、RC-5 门同规）。

静态侧证（只读）：`ir_generator.zig:2637–2673` 的 `generateIfStmt` 里两条臂尾**只可能** `br` 到本 if 自己的 `if_merge`（`if (!isBlockTerminated()) setTerminator(.{ .br = merge_block })`），不存在指向兄弟臂内部的边 ⇒ 风险只剩「该 merge 块号是否排进 `[else_idx, end_idx)` 帧内」，此项静态不可判，由 D-1 实测判定。

## 2. 语料暴露

- `fuzzy_scripts_720/pass/` 68 脚本中 **15 个含 `elseif`**（f007/f025/f028/f032/f038/f044/f065/f067/f070/f087/…），全部现行 PASS ⇒ 触发需要**特定块序**（见 §3），语料未产生该组合。
- **R4 实测更正（§3.5.5 第 1 条）**：触发条件不是 `elseif` 关键字，而是**块序几何**（共享 merge 块号排在臂块之前）。`nested_merge_idx` 站点在 f026、f067_min_repro、f160 这三个 **`elseif` 计数为 0** 的语料脚本同样命中 ⇒ 任何以「含 elseif」为筛选条件的风险估算都会低估，须按 §3.5.1/3.5.3 的站点命中数记账。
- 结论同 CODEGEN-005：语料绿 ≠ 形状覆盖。本单 9 形是新的覆盖缺口，补入语料需重冻结基线（既有裁决项）。

## 3. 取证（只读；IR 层 + 发射层）

### 3.1 IR 块序 A/B（`--compile --dump-ir`）

**绿（形状2，无 elseif）**：
```
entry(0) → br cond, if_then_0, if_else_1
if_then_0(1)  echo; br if_merge_2
if_else_1(2)  for-init; br for_cond_4     ← for-init 块号 2 < merge 块号 3
if_merge_2(3) ret
for_cond_4(4) / for_body_5(5) / for_exit_7(6 → br if_merge_2)
```

**红（形状1，elseif 链 + 末臂 for）**：
```
entry(0) → br cond, if_then_0, if_else_1
if_then_0(1)   echo; br if_merge_2
if_else_1(2)   嵌套 cond; br cond, if_then_3, if_else_4
if_merge_2(3)  ret                          ← merge 先于它要合并的两个臂
if_then_3(4)   echo; br if_merge_2
if_else_4(5)   for-init; br for_cond_7     ← for-init 块号 5 > merge 块号 3
for_cond_7(6) / for_body_8(7) / for_exit_10(8 → br if_merge_2)
```

**红（形状9，for 在首个 if 臂）**：
```
entry(0) / if_then_0(1: for-init; br for_cond_4) / if_else_1(2: 嵌套 cond)
if_merge_2(3: ret)
for_cond_4(4) / for_body_5(5) / for_exit_7(6 → br if_merge_2)
if_then_8(7 → br if_merge_2) / if_else_9(8 → br if_merge_2)
```

IR 本身**语义正确**（三臂 echo 站点、循环三块、出口边 `br if_merge_2` 齐全）⇒ 致损在**发射侧对乱序 merge 的处理**，不在 ir_generator 的图语义。

### 3.2 发射侧截断点（形状1，`ZIGPHP_AOT_KEEP_TEMP=1` → `.zigphp_aot_build_22670/main.zig`，1351 行）

| 位置 | 内容 |
|---|---|
| :117–:124 | 外层条件 `getGlobalVar("$mode")` + `php_identical` |
| :125–:173 | `if (...)` then 臂 echo（含异常清理链） |
| :174–:185 | else 分支进入，嵌套条件发射 |
| :186–:234 | elseif 臂 echo |
| :235–:251 | 末 else 臂进入，`$hit=0` `:241`、`$sum=0` `:246`、`$i=0` `:251` |
| :254、:257 | for 的上界常量 `reg_13 = 3`、步长常量 `reg_16 = 1` |
| **:258–:259** | **两层右花括号闭合 ⇒ 发射到此为止** |
| :260–:279 | Cleanup + `return runtime.Value.initNull()` |

⇒ **`for` 循环头 `for_cond_7` 从未被派发**（全文件无 `__for_*` 标签），臂尾 echo 随循环一起丢失，只剩 for-init 的赋值与两个常量 —— 与 CODEGEN-005 RC-2 登记的「臂内嵌 `for` 塌缩为仅初始化」**同一表征**。

形状9 的表征不同（三臂串联）：首个 if 臂的循环被推到链外重发（RC-4 的「循环外重发」家族），而**臂尾 `br if_merge_` 未发** ⇒ 直落下一臂。

### 3.3 trace 取证轮 R1（实测，2026-10-04，非行为 stderr 插桩）

插桩口径：`native_linker.zig` 内 16 处 `std.debug.print("[C06T-*]", ...)`，**全部只写 stderr、不经 `writer`** ⇒ 生成 `main.zig` 逐字节不变（复验方式：R1 与 R2 两轮插桩产物 `main.zig` 互相 `cmp`，并与还原后 clean 轮比对）。门：`bash /tmp/c006_trace_run.sh <tag>`（临时脚本，轮次结束删除）。

R1 读数（`/tmp/c006_trace_r1/*.err`，2026-10-04）：

| 形 | 判定 | 关键 trace 事件（walker 视角） |
|---|---|---|
| 1 else 臂含 for | DIFF 空输出 | `WALK i=0 range=0..9 entry` →（无任何子帧）→ `BAIL i=4 start=0 end=9 **ret=1**` |
| 2 绿（if/else 含 for） | IDENTICAL | `WALK 0..7 entry` → `WALK i=4 range=4..7 for_cond_4` → `FOR head=4 end=7 ret_i=7` → `BAIL i=4 ret=1` |
| 3 绿（else 只 echo） | IDENTICAL | `WALK 0..6 entry` → `BAIL i=4 ret=1` |
| 4 elseif 臂含 for | DIFF 串臂 | `WALK 0..9 entry` → `WALK range=4..9`：`if_then_3`、`if_else_4`、`for_cond_7` 顺序线性走 → `FOR head=6 end=9 ret_i=9` → `BAIL i=4 start=0 ret=1` |
| 5 else 臂含 while | DIFF 空输出 | `WALK 0..9 entry` → `BAIL i=4 ret=1` |
| 6 形状1+链尾语句 | DIFF 仅尾语句 | 同形 1 |
| 7 函数上下文 | DIFF 跑错臂 | `WALK f=c006_tl_f7 0..8 entry` → `WALK i=3 range=3..8 if_then_3 inCB=1` → `BAIL i=1 start=0 ret=1` |
| 8 两级 elseif | DIFF 空输出 | `WALK 0..11 entry` → `BAIL i=4 ret=1` |
| 9 首个 if 臂含 for | DIFF 三臂全跑 | `WALK 0..9 entry` → `WALK i=4 range=4..9 for_cond_4 defer=1` → `FOR head=4 end=9 ret_i=7` → `WALK i=7 if_then_8`、`i=8 if_else_9`（**臂块在 then 帧内被线性吞掉**）→ `SKIP i=1,2` → `WALK i=3 if_merge_2` |

**R1 已定的三条事实**（原 §4 假设的前两条由此转为实测）：

1. **`generateIfFromLabels` 全程 0 次进入**（9 形无一条 `[C06T-GIFL]`）⇒ 本族发射**不走 GIFL**，§4 里把 `generateIfFromLabels` 的 merge/else 解析列为站点是错的；实际归属是 `generateLabelDrivenBlockRange` 内部的**行内 `.cond_br` 处理器**（干净树 :8357 起，else 臂链在 :9583/:9748 区；锚点为还原后工作区 blob `3ae7b34e`，32546 行）。
2. **红形共性 = walker 在臂块起点 `BAIL` 且 `ret=1`**：链共享的 `if_merge_` 块（含函数尾 `ret`）块号排在臂块之前，行内处理器把它当 merge 延续发射 ⇒ `return_generated` 置位 → 行走头部不可达检查（:7241）把排在后面的 sibling 臂/循环块整体 `markReachableRestBlocks` 吞标 ⇒ 形 1/5/6/8 末臂全丢。
3. **循环头未被派发**：形 1/5 的 `for_cond_/while_cond_` 从未出现在任何 `WALK/FOR` 事件里（对照形 2 有 `WALK … for_cond_4` + `FOR`），与 §3.2「全文件无 `__for_*` 标签」一致 ⇒ 形 4/9 虽派发了循环，但派发发生在**链的线性延续帧**里（`range=4..9`），臂间互斥性因此丧失。

**R2（已完成，读数见 §3.4）**：在行内 `.cond_br` 处理器补 `[C06T-NESTCB] / [C06T-EO-ORD] / [C06T-EO-Ooo] / [C06T-OBBR-*] / [C06T-ICMERGE]` 五类探针（新增 7 处，合计 23 行插桩），证实「elseif 链走 out-of-order 分支（`nested_merge_idx < nested_then_idx`）→ 臂尾 `.br` 只做 `materializeEdgePhi`、不派发循环头」以及 merge 的 `ret` 在 `:10423` 处理器层续延处冒泡。

**R3（clean 轮还原复验，实测）**：插桩结束后 `native_linker.zig` 已从 `/tmp/nl_backup_c006_d6045035.zig` 还原并逐项核对——

| 项 | 读数 |
|---|---|
| 还原后工作区 | md5 `d6045035c43ebc9cdef25b31ca1248ab`、32546 行、`grep -c "C06T-" = 0`、`git diff --numstat` 空、暂存区仍 `+128/−23`、index blob `3ae7b34e…` |
| 发射中性（三方比对） | clean 轮 9 份 `main.zig` 与 **R1** 比对 `same=9 differs=0`，与 **R2** 比对 `same=9 differs=0` ⇒ 两轮插桩对生成码逐字节无影响 |
| 本单门（clean 树重跑） | `C006_TL_GATE_DONE total=9 same=2 differs=7`，7 个红形的 `aot=[...]` 载荷与 §1 表逐字符相同 ⇒ 修复前基线可复现 |
| 门 A（17 形） | `PROBE_DONE total=17 same=17 differs=0` ⇒ RC-5 批次未被取证轮污染 |



### 3.4 trace 取证轮 R2（实测，2026-10-04，行内 `.cond_br` 处理器插桩）

同一门、同一 9 形，`[C06T-NESTCB]/[C06T-EO-Ooo]/[C06T-EO-ORD]/[C06T-OBBR-*]/[C06T-ICMERGE]` 五类探针（`/tmp/c006_trace2/*.err`）。**R1 与 R2 两轮生成的 9 份 `main.zig` 逐字节相同（identical=9 differs=0）** ⇒ 插桩对发射零影响。

| 形 | ooo | 路径与关键读数（块号省略前缀，`if_else_4` = 末 else 臂） |
|---|---|---|
| 1 else 臂含 for | **1** | `NESTCB ei=2 nti=4(if_then_3) nelse=if_else_4 **nmi=3(if_merge_2)**` → `EO-Ooo` → `OBBR-then tgt=if_merge_2 loophead=0` ✓ → **`OBBR-ne tgt=for_cond_7 idx=6 loophead=1`（此处只 `materializeEdgePhi`，无循环派发）** → `ICMERGE mi=3 term=ret ret=0` → `BAIL i=4 ret=1` |
| 5 else 臂含 while | 1 | 同形 1，`OBBR-ne tgt=while_cond_6 idx=6 loophead=1` |
| 6 形状1+链尾语句 | 1 | 同形 1 |
| 8 两级 elseif | 1 | `EO-Ooo` → 仅 `OBBR-then`（三级链落 `chain_unwind`，该路径同样无臂尾循环派发）→ `ICMERGE` → `BAIL i=4 ret=1` |
| **3 绿（else 只 echo）** | 1 | **同一条 `EO-Ooo` 分支**，但 `OBBR-ne tgt=if_merge_2 idx=3 **loophead=0**` ⇒ 无循环可派发 ⇒ 输出等值 |
| 4 elseif 臂含 for | 0 | `NESTCB **nmi=6(for_cond_7)**` ⇒ 走有序分支 `EO-ORD nti=4 cs18_end=9` ⇒ `WALK range=4..9` 依次线性吞 `if_then_3`(4)、**`if_else_4`(5)**、`for_cond_7`(6) → `FOR head=6 end=9 ret_i=9` → `ICMERGE` → `BAIL` |
| 7 函数上下文 | 0 | 同形 4（`nmi=5(for_cond_7)`，`EO-ORD cs18_end=8`），`WALK i=3 if_then_3` 后 `BAIL i=1 ret=1` ⇒ 跑错臂 |
| 9 首个 if 臂含 for | — | then 臂循环由 defer 派发（`FOR head=4 **end=9** ret_i=7`）→ **同帧继续 `WALK i=7 if_then_8`、`i=8 if_else_9`** → `NESTCB nti=7` 因 7/8 已 processed 而落空 → `SKIP 1,2` → `WALK i=3 if_merge_2` |

**判据（绿/红唯一分界，实测）**：`EO-Ooo` 分支的臂尾 `.br` 目标是否 `isLoopHeadLabel == 1`（形 3 绿 loophead=0 / 形 1·5·6 红 loophead=1，其余条件完全相同）。

### 3.5 修复面前置影子实测 R4（流程规约 (a) 强制；2026-10-04 实测；全 88 脚本；发射侧零改动）

插桩 = 六个非行为 stderr 探针：`[S06A]`（四处臂尾 `.br` 站点，报 `src_line`/函数/臂/目标标签/`lh`=是否 `isLoopHeadLabel`）、`[S06B1]`（`nested_merge_idx` 求解后 `blk0b`）、`[S06B2]`（有序分支 `cs18_end`）、`[S06C]`（行走器线性进入块）、`[S06C2]`（then 帧上界 `then_end` 与该帧内兄弟臂计数）、`[S06D]`（bail 处范围内臂块计数）。

**中性证明（实测）**：`S06_SHADOW_DONE total=88 hit_scripts=79 compile_fail=0 drift_ok=68 drift_diff=0 drift_norow=20` ⇒ 68 个语料脚本的 `main.zig` md5+行数与冻结基线逐字节一致，20 个 `tmp/` 探针无冻结行（预期）。还原后复验：`md5=d6045035c43ebc9cdef25b31ca1248ab`、32546 行、`S06` 残留 0、工作区对暂存区零差、暂存仍 `+128/−23`、index blob `3ae7b34e`、模板 md5 未变。

**取证纪律更正**：聚合前剔除 `raw/probe1.err` —— 那是我启动全量前的**冒烟夹具** `/tmp/probe1.php`（已随冒烟删除），不属语料也不属本单 9 形，其读数不得作证据。

#### 3.5.1 逐标签命中面（事件=全部 88 脚本；脚本按语料 68 / 探针 20 分列）

| 标签 | 事件 | 语料脚本 | 探针脚本 | 判别性判定（实测） |
|---|---|---|---|---|
| `S06A` 臂尾 `.br` | 19 | 4 | 6 | **可判别**：红形只以窄循环头出现，语料只以 `if_merge_`/`foreach_increment_` 出现 |
| `S06B1` 链 merge 求解 | 70 | 34 | 9 | 其中 `lh=1` 共 11 事件 / **8 个语料脚本 + 2 红探针** ⇒ 非判别（见 3.5.3） |
| `S06B2` 有序分支界 | 26 | 20 | 2 | `no_truncate=1` 出现在 17 个脚本（多为 `cs18_end == end_idx` 的平凡等号），**红形与绿形同读数 ⇒ 非判别** |
| `S06C` 线性进入块 | 80 | 38 | 3 | 单独非判别；**派生签名判别**（见 3.5.4） |
| `S06C2` then 帧界 | 11 | 7 | 1 | `arms≥1` 5 事件里 **4 个来自通过语料** ⇒ 非判别 |
| `S06D` bail 臂计数 | 342 | 61 | 16 | 该探针未查 `processed`，**过计数**（通过脚本同样 `arms=2~4`）⇒ 非判据，仅作现场感 |

#### 3.5.2 A 类：窄派发集 vs 宽 `isLoopHeadLabel` —— 实测分野（决定修复谓词）

| 目标标签类 | 事件 | 归因 | 是否须派发 |
|---|---|---|---|
| 窄集（`for_cond_`/`while_cond_`/`foreach_cond_`/`do_while_body_`） | 4 | **语料 0**；红探针 形1（`for_cond_7`）、形5（`while_cond_6`）、形6（`for_cond_7`）+ `perf001_hotspot_probe_tmp`（`for_cond_10`） | **是**（本单唯一红形触发） |
| 宽集独有（`foreach_increment_*`） | 5 | 语料 3 脚本：f044（`deepDiff`→`foreach_increment_2`、`validateSchema`→`_19`）、f067（`JsonDiff::diff`→`_7`）、f160（`VirtualFS::normalize` then 与 else 各一次 →`_2`），**现行全部 PASS** | **否** —— 属回边/latch 形，已由 RC-4/RC-5 收口 |
| `lh=0`（`if_merge_*` 回落 merge） | 10 | 语料 f010（`Container::make`→`if_merge_8`）、f067（`JsonPath::query`→`if_merge_12`，:9122 与 :10089 两处）等 | 否 —— 维持 `materializeEdgePhi` |
| 模板 ② 的三条例外形态（`if_then_`+`if_merge_` / `ternary_then_`+`ternary_merge_` / `coalesce_rhs_`+`coalesce_merge_`） | **0** | 88 脚本四处臂尾站点无任何此类目标 | **本轮不纳入**（未实测即不写，规约 (a)） |

⇒ **A 的实测口径 = 窄四前缀，且必须排除 `isLoopHeadLabel`**（否则命中 f044/f067/f160 三个通过脚本，属真实回归）。

#### 3.5.3 B 类：`nested_merge_idx` 解成循环头 —— 站点定位，谓词未闭合

`lh=1` 的 11 个事件：**8 个语料脚本**（f007 `StringUtils::levenshtein2`→`for_cond_5`、f026 `LinkedList::pop`→`while_cond_4`、f044 `JsonTools::deepDiff`→`foreach_cond_0`、f067 `JsonDiff::diff`→`foreach_cond_5` 与 `foreach_increment_7`、f067_min_repro→`while_cond_4`、f102 两次（`foreach_cond_4`/`_6`）、f124 `ContainerOrchestrator::autoscale`→`foreach_cond_12`、f160 `VirtualFS::normalize`→`foreach_increment_2`，**全部现行 PASS 且已冻结**）+ 2 个红探针（形4、形7 →`for_cond_7`）。

⇒ 直接改 `nested_merge_idx` 求解会触碰 **8/68 已冻结通过脚本**，而该读数在红/绿两侧同现 ⇒ **不构成可落地的判别谓词**。另：形 7（函数上下文跑错臂）在 B1/B2/C/C2 五类探针下**无任何独有误臂读数**（仅一条 `S06C i=3 if_then_3`）⇒ 其错臂取用路径未经探针覆盖，**B 需要第二轮细探针（在有序分支内报「实际取用的 else 块号 + 区间」）才能出「字面等于实测」的修法**。

#### 3.5.4 兄弟臂线性吞签名（由 `[S06C]` 派生；本轮唯一干净的红/绿分界）

判据：同一行走区间 `[range_start, end)` 内，线性进入**同一 if 的 then 臂与紧邻兄弟 else 臂**（`if_then_N` 与 `if_else_{N+1}` 同现）。

| 命中 | 读数 | 门状态 |
|---|---|---|
| `c006_tl_elseif_loop_tmp`（形4） | `range=4..9 then=3 else=4` | 红（互斥性丧失） |
| `c006_tl_ifarm_loop_tmp`（形9） | `range=4..9 then=8 else=9` | 红（三臂全执行） |
| **语料 68 脚本** | **0 命中** | — |

⇒ B 的「串臂」侧（形 4）与 C（形 9）在这一签名下同形，且语料零命中 ⇒ 若把修复谓词写成**「有序分支/then 帧的区间上界以兄弟臂块为界」**（而非改 `nested_merge_idx` 本身），实测命中面为 **0 个语料脚本**。此口径仅覆盖形 4/9，**不覆盖形 7**。

#### 3.5.5 三条口径更正（实测否证先前工单表述）

1. **§2 与 §4 末行的「B/C 改动面 = 全部含 `elseif` 的语料脚本（15/68）」被否证**：B1 `lh=1` 的 8 个语料脚本里 f026、f067_min_repro、f160 **源码 `elseif` 计数为 0** ⇒ 站点是通用嵌套 if，不是 elseif 专属；真实风险面按 3.5.3 的 8 脚本 + 3.5.4 的 0 命中记账。
2. **§4.1 步骤 3 的谓词写错**：原稿用 `isLoopHeadLabel`（宽集）⇒ 会命中 f044/f067/f160；按 3.5.2 必须改为窄四前缀。
3. **§4.1 R-1「A 单独落地可能让形 9 更红」被实测否证**：形 9 在四处臂尾站点**无任何 `[S06A]` 读数**（其读数为 `S06B1 nmi=if_merge_2 lh=0` + `S06C2 arms=2` + `S06C` 双臂）⇒ A 的派发根本不被形 9 几何触达，A 不会改变形 9。
4. **§4 A 行的「1/5/6/8」缩为「1/5/6」**：形 8（两级 elseif）在四处站点的臂尾读数只有 `tgt=if_merge_2 lh=0`，三级链实际落 `chain_unwind`（:9111 / :10064）——**该路径本轮未插桩**，属第五类站点，其臂尾是否也缺派发**未测** ⇒ 形 8 的修复另开影子轮，不得与 A 同批声称。
5. **§5 门 1 的「`total=9 same=9`」是终态门，不是 A 批门**：按 3.5.2/3.5.4 实测口径，A 批的可达终态是 `same=5 differs=4`（1/5/6 转绿）；A+兄弟臂界口径批为 `same=7 differs=2`（+4/9）；形 7 与形 8 分别被 R5 的两个未闭合口径挡住 ⇒ 验收必须按批次分级，否则会把「未修」误记为「劣化」。

#### 3.5.6 R4 收尾复验（实测，2026-10-04）

还原 ⇒ 复验 ⇒ 重建 ⇒ 五门，串行、无并发编译：

| 步 | 读数 |
|---|---|
| 还原复验 | `md5=d6045035c43ebc9cdef25b31ca1248ab`（= 影子前原值）、32546 行、`S06` 残留 0、`git diff` 工作区 vs 暂存区零差、暂存仍 `+128/−23`、index blob `3ae7b34e…`、模板 md5 `008b7b63…` 未变 |
| clean 重建 | `clean_build_rc=0 elapsed=64s` |
| 门 A（17 形等值） | `PROBE_DONE total=17 same=17 differs=0` |
| 本单门（9 形） | `C006_TL_GATE_DONE total=9 same=2 differs=7`（与 R3 逐字节同判定 ⇒ 影子轮未改发射） |
| RC-4 门 | `RC4_PROBE_DONE total=4 same=3 differs=1`（唯一红点 = REF-003 `rc=139`） |
| RC-5 八形合串 | `IDENTICAL\|c005_rc5_merge_loss_tmp\|rc=0` |
| do-while 门 | `DOWHILE_PROBE_DONE total=2 same=2 differs=0` |

**官方 68 回归 / 冻结漂移 / 确定性巡检 / 抽查 / `zig build test` 本轮未重跑**（口径记账）：还原后的 `native_linker.zig` 与已全门绿过的 RC-5 代次**逐字节同一**（md5 + 行数 + 零残留三重证明），且 R4 主扫描自身已给出更强的覆盖面证据 —— `drift_ok=68 drift_diff=0`（68 个语料脚本 `main.zig` 在插桩代次下即与冻结基线逐字节一致）。源码未变时代重跑等同重测同一二进制，故只跑五形等值门即可判定「影子轮发射中性」。

### 3.6 R5 细影子轮（流程规约 (a) 的第二轮；2026-10-04 实测；96 脚本 = 68 语料 `pass/` + 28 永久探针；发射侧零改动）

R4 留了两个未闭合口径（形 7 的错臂取用、形 8 的 `chain_unwind` 站点），本轮把站点级判据补测到「字面可落地」或「判据不成立」为止。

#### 3.6.1 插桩口径与发射中性（三重证明）

12 类标签 / 17 处插入，全部 `std.debug.print` 只写 stderr、不经 `writer`；孪生块用 `allow_multiple` + `@src().line` 区分：

| 标签 | 站点（干净树行号，blob `3ae7b34e` / 32546 行 / md5 `d6045035…`，本轮行动前已 re-grep） | 报什么 |
|---|---|---|
| `[S06H]` | 行内 `.cond_br` 处理器 then/else 指针扫描之后（:8357 区内） | `i/range_start/end_idx/block.label/then_bi/else_bi` + 三者 processed |
| `[S06M]`+`[S06T]` | :8651（then 臂帧递归前；`then_end` 求解 :8629–:8646） | `blk_i/then_end/end_idx/else_bi/else_branch_start`、`inh`（外层 else 臂是否落帧内）、`sib`（帧内未 processed 的 `if_then_/if_else_` 块数与首块） |
| `[S06E]`+`[S06T2]` | :9977（有序分支递归前；`cs18_end` 求解 :9965–:9975） | `nti/nmi/cs18_end/end_idx`、`nested_cb.else_block` 指针扫描索引 + `in/pel` + 同款 `sib` |
| `[S06K]` | :9111 / :10064（`chain_unwind` 每轮起始） | 本轮 `chain_cb` then/else 标签、then 索引与 processed、`end_idx` |
| `[S06L]` | :9128 / :10081（`guard_form` 判定后） | `guard_form`、else 目标索引/标签/终止符 tag/processed |
| `[S06R]` | :9143 / :10096（`if (!else_is_back_edge) break`） | `else_is_back_edge`、`current_loop_cond_block` |
| `[S06N]` | :9153 之后的单臂出口 | 非守卫 + 回边 ⇒ 单臂守卫 if 出口 |
| `[S06G]` | :9160 / :10113（守卫式臂尾站点） | `cti/标签/终止符 tag/`.br` 目标与窄口径循环头标志 |
| `[S06Q]` `[S06P]` | :9185 / :10138、`chain_cb = e_term2.cond_br` | 链是否终止 / 是否续下一层 |

中性证明：① 三代次插桩（stage-1 = H/E/G ⇒ stage-1b = +K/L/M/N/P/Q/R ⇒ stage-1c = +T/T2）下 15 个永久探针的 `main.zig` md5+行数 **两轮 diff 皆空**；② 全量扫描 **`drift=OK 68/68`**（对冻结基线逐字节）、`compile_fail=0`、`rows=96`；③ 收尾还原复验 md5/行数/零残留/暂存 `+128/−23`/blob 全等（见 3.6.6）。
**口径自查**：首轮误用 `--optimize=release-fast` 做漂移核对 ⇒ 出现假 DIFF；冻结基线采集口径是 `--compile --no-debug-info`（默认档，见 `fuzzy_scripts_720/tmp/c005_full_drift_tmp.sh`），停轮纠正后重跑 ⇒ 结论以重跑为准。

#### 3.6.2 PB（有序分支兄弟臂，形 4/7）：判据已闭合，但**结构判据命中面不为 0**

`[S06E]` 裸判据 `in=1 && pel=0` ⇒ **26 事件 / 22 脚本 = 语料 20 + 探针 2**。逐条读数显示 20 个语料事件的 else 目标绝大多数是 **merge 块**（`if_merge_`/`coalesce_merge_`/`ternary_merge_`，如 `HttpRequestBuilder::build nti=3 nmi=4(if_merge_3) cs18_end=5 else=4(if_merge_3)`）⇒ 帧内含 merge 属正常形态，裸判据不可用（与 §3.5.3 的 B1 结论同向、更强）。
收紧为「帧内存在未 processed 的 `if_then_/if_else_` 臂块」（`[S06T2] sib>=1`）⇒ **4 事件 / 4 脚本**：

| 命中 | 读数 | 门状态 |
|---|---|---|
| `f044_json_deepops_merge_diff`（`JsonDiff::diff`） | `nti=6(if_then_2) cs18_end=26 sib=9 first=7(if_else_3)` | 冻结 PASS |
| `f080_db_transaction_mvcc_deadlock`（`MVCCStore::write`） | `nti=3(if_then_2) cs18_end=6 sib=1 first=4(if_else_3)` | 冻结 PASS |
| `c006_tl_elseif_loop_tmp`（形 4） | `nti=4(if_then_3) cs18_end=9 sib=1 first=5(if_else_4)` | 红 |
| `c006_tl_fncontext_loop_tmp`（形 7） | `nti=3(if_then_3) cs18_end=8 sib=1 first=4(if_else_4)` | 红 |

⇒ **推翻 §3.5.4 的乐观口径**（那里按 `[S06C]` 兄弟臂线性签名得「语料 0 命中」）：换成站点内的 `sib` 口径后，语料命中面为 **2 个当前通过的脚本**，且 `f044` 一形 `sib=9` 属正常嵌套 ⇒ 「以兄弟臂块为界」写成标签前缀 + processed 的**结构判据不可落地**；B 需要**臂归属判据**（该块是否由**本 cond_br 的 else 目标沿链可达**）才能把形 4/7 与 f044/f080 分开。这是设计决策，不是行补丁 ⇒ **形 4/7 保持 OPEN**。

#### 3.6.3 PC（then 帧吞兄弟臂，形 9）：原 C 判据被否证

`[S06M]` **11 事件 / 8 脚本**中 `inh`（外层 `else_bi` 落在 `[blk_i, then_end)`）**全为 0** ⇒ §4 C 行原写的「帧上界以 `else_bi` 为界」在语料与探针上都不成立（形 9 读数：`blk=4(for_cond_4) then_end=9 end=9 ei=2(if_else_1) ebs=null inh=0`）。
改用 `[S06T] sib>=1` ⇒ **5 事件 = 语料 4 + 形 9**：`f095 DeadCodeElimination::optimize`(sib=1 first=`if_then_21`)、`f102 RefCountGC::release`(sib=1 first=`if_then_7`)、`f124 ContainerOrchestrator::autoscale`(sib=1 first=`if_then_10`)、`f177 Graph::hasCycle`(sib=1 first=`if_then_10`) 均为**冻结 PASS**，形 9 为 `sib=2 first=7(if_then_8)`。
⇒ 语料 4 例是「循环体内合法嵌套 if」的臂块，与形 9「链的兄弟臂被同帧吞掉」在结构口径上**不可分** ⇒ C 与 B 共用同一个未闭合前置：**臂归属判据**。**形 9 保持 OPEN**。

#### 3.6.4 PD（`chain_unwind` 裸 break，形 8）：站点闭合，语料命中面 = 0 ⇒ 新增第五类可落地候选

| 读数 | 实测 |
|---|---|
| `[S06K]`（链每轮起始） | **2 事件 / 2 脚本** = `f067_json_parser_schema_path_diff` + 形 8；两条均有后继 `[S06L]` ⇒ `ch_ti==null` 与 `processed.contains(cti)` 两个提前 bail **未触发** |
| `[S06L]` `guard_form` | 2 事件 **全为 `guard=0`**（形 8：`cti=6 lbl=if_then_6 guard=0 els=7(if_else_7) elsterm=br pel=0`） |
| `[S06G]`（守卫式臂尾站点） | **全 96 脚本 0 事件** ⇒ 该路径本轮不可达 ⇒ §7 原记「形 8 要移植 A 类同款模板到 `chain_unwind` 臂尾」**否证** |
| `[S06R]` | 2 事件 = 形 8 `be=0 clcb=null`（顶层脚本体，无当前循环）与 f067 `be=1`（走 `[S06N]` 单臂守卫出口，1 事件） |
| `[S06P]`/`[S06Q]` | **全 0** ⇒ `chain_unwind` 实测**从不进入第二轮**，注释所述「沿链逐层展开」在多级链上从未生效 |

⇒ 形 8 的缺失派发点 = `if (!else_is_back_edge) break :chain_unwind;`（:9143 / :10096）的**裸 break**：三级链第二级的 else 目标（`if_else_7`，尾 `br` 到链 merge）既非守卫形态、又非本循环回边（顶层体 `clcb=null`）⇒ 连同臂体与末 else 臂（含 for）整体丢弃。
**风险面 = 0 个语料脚本**（唯一进入该链的语料脚本 f067 走 `be=1` 的另一出口）⇒ 以实测谓词 `!guard_form && !else_is_back_edge` 门控的新派发分支，其漂移风险与 A 类同级（语料零命中、仅探针可达），可与 A 同批或单独成批。

#### 3.6.5 按实测重排的批次可达终态

| 批次 | 内容 | 预期本单门（9 形） |
|---|---|---|
| A | 四处臂尾 `.br` 的窄四前缀循环头派发（§4.1） | `same=5 differs=4`（1/5/6 转绿） |
| A + PD | 再加 `chain_unwind` 裸 break 处按臂派发 | **`same=6 differs=3`**（+8） |
| 需臂归属判据 | B（形 4/7）与 C（形 9） | 未设计前不动共享区间语义 ⇒ 3 形保持红 |

#### 3.6.6 R5 收尾复验（实测，2026-10-04）

| 步 | 实测读数（closeout 链，2026-10-04 15:17 收） |
|---|---|
| 还原复验（7 项全等） | `md5=d6045035c43ebc9cdef25b31ca1248ab`、`lines=32546`、`S06` 残留 `0`、工作区 vs 暂存区差分行 `0`、暂存仍 `+128 / −23`、index blob `3ae7b34e08f4d77991427c69fde793a01ddbc1b6`、`runtime_lib_template.zig` md5 `008b7b639f1069cb73e443064e115ed1` |
| clean 重建 | `zig build` **`rc=0`，耗时 65s**（探针移除后重新编译出干净发射器） |
| 门 A（17 形等值） | `PROBE_DONE total=17 same=17 differs=0` |
| 本单 9 形门 | `C006_TL_GATE_DONE total=9 same=2 differs=7`（绿：形 2/3；红：1/4/5/6/7/8/9 —— 与 R5 前**逐形一致**，影子轮未改变任何输出） |
| RC-4 门 | `RC4_PROBE_DONE total=4 same=3 differs=1`（唯一红点 `ref003_crash_attr_tmp` `rc=139` 段错误，W3 grow-then-continue 缺失 ⇒ 归 REF-003，非本单劣化） |
| RC-5 八形合串 | `IDENTICAL`（`rc=0`） |
| do-while 门 | `DOWHILE_PROBE_DONE total=2 same=2 differs=0` |
| 语料完整性 | `fuzzy_scripts_720` `.php` 总数 **364**（`tmp/` 183、pass 集 68），`git status` 删除记录 **0** 条 |
| 未重跑项与理由 | 官方 68 回归 / 冻结漂移 / 确定性巡检 / 抽查 / `zig build test` 本轮未重跑。理由：还原后源码与「已全门绿过」的 RC-5 代次**逐字节同一**（七项复验全等即该前提的证据），且 R5 影子轮的 **`drift=OK 68/68` + `compile_fail=0`** 是在**含探针代次**上跑的更强证据（同源码代次两跑，结论一致）。A/D 批落地时按 §5 第 3 条恢复全套门。 |

⇒ **R5 判定**：17 处插桩对发射**逐字节中性**（三代次 `main.zig` md5 diff 皆空 + 全语料漂移零 + 五门读数与插桩前完全一致），三个未闭合口径全部拿到实测答案：**PB 语料面 2**（结构判据不可落地）、**PC 语料面 4**（原判据否证）、**PD 语料面 0**（新立 D 类，与 A 同级风险）。B/C 的共享前置收敛为同一件未设计物：**臂归属判据**。

### 3.7 R6 臂归属判据设计轮（#59；2026-10-04 实测；114 脚本 = 68 语料 `pass/` + 46 永久探针；发射侧零改动）

**待验命题**（§3.6.2/§3.6.3 收敛出的前置）：把「块是否在帧内」换成「块是否由**本 `cond_br` 的 else 目标沿链可达**（指针归属）」，能否把红形 4/7/9 与 R5 误报的六个通过脚本分开。

#### 3.7.1 插桩口径（4 标签 / 5 块，全部 `std.debug.print` 只写 stderr、不经 `writer`）

归属集合作法（四站点同法，仅帧与根不同）：从根节点起，每层收 `then_block` 与 `else_block` 的索引（指针等值 → `tryFindBlockIndex`，**不用 `findBlockIndex`，其未命中会 panic**），仅当 else 目标终止符为 `.cond_br` 才续层，深度 ≤8、集合 ≤16；命中条件 = 索引**严格落在帧内** 且 `!processed` 且 `instructions.items.len > 0` 且标签不含 `_merge_` 且非窄四前缀。

| 标签 | 站点（干净树行号代次 `3ae7b34e`） | 帧 | 归属链根 |
|---|---|---|---|
| `[S07C1]` | `then_end` 求解之后、then 帧递归之前（:8646 后） | `[blk_i, then_end)` | `cond_br_data` |
| `[S07C2]` | `cs18_end` 求解之后、有序分支递归之前（:9976 后） | `[nti, cs18_end)` | `nested_cb` |
| `[S07C3]` | else 臂循环头派发之前（:9719 前） | `[blk_i, end_idx)` | `cond_br_data` |
| `[S07CD]` ×2 孪生 | `chain_unwind` 单臂守卫行走之前（:9153 / :10106） | `[cti, end_idx)` | `chain_cb` |

**中性证明**：含探针代次上全量冻结基线漂移 **`S06_R6_DONE total=114 drift_ok=68 drift_diff=0 notemp=0 norow=0 compile_fail=0`**；还原复验 7 项全等（`md5=d6045035c43ebc9cdef25b31ca1248ab`、`lines=32546`、`S07` 残留 0、工作区 vs 暂存区差分行 0、暂存仍 `+128 / −23`、blob `3ae7b34e…`、模板 md5 `008b7b63…`），clean 重建 `rc=0` 64s。读数规模：`C1` 15 读数 / 11 脚本，`C2` 26 / 22，`C3` 40 / 22，`CD` 1 / 1。

#### 3.7.2 实测命中面：指针归属判据**不可判别**（12 命中事件 = 红 3 + 绿 9）

| 站点 | 脚本 | 函数 | 读数 | 门状态 |
|---|---|---|---|---|
| C2 | 形 4 `c006_tl_elseif_loop` | `__main__` | `nti=4(if_then_3) cs18_end=9 nmi=6 nce=2 hits=1 first=5(if_else_4)` | 红 |
| C2 | 形 7 `c006_tl_fncontext_loop` | `c006_tl_f7` | `nti=3(if_then_3) cs18_end=8 nmi=5 nce=2 hits=1 first=4(if_else_4)` | 红 |
| C1 | 形 9 `c006_tl_ifarm_loop` | `__main__` | `blk=4(for_cond_4) then_end=9 ei=2 nce=4 hits=2 first=7(if_then_8)` | 红 |
| C2 | `f025_coding_hamming_rle_lzw_crc` | `HammingCode::introduceError` | `nti=5(ternary_then_4) cs18_end=8 nmi=7 nce=2 hits=1 first=6(ternary_else_5)` | 冻结 PASS |
| C2 | `f043_math_functions_full` | `MathTools::median` | `nti=3(ternary_then_2) cs18_end=6 nmi=5 nce=2 hits=1 first=4(ternary_else_3)` | 冻结 PASS |
| C2 | `f072_type_inference_hindley_milner` | `TypeInferer::inferArray` | 同 `f043` 逐字段全等 | 冻结 PASS |
| C2 | `f080_db_transaction_mvcc_deadlock` | `MVCCStore::write` | `nti=3(if_then_2) cs18_end=6 nmi=5 nce=2 hits=1 first=4(if_else_3)` | 冻结 PASS |
| C2 | `f067_json_parser_schema_path_diff` | `JsonDiff::diff` | `nti=6(if_then_2) cs18_end=26 nmi=9 nce=4 hits=2 first=7(if_else_3)` | 冻结 PASS |
| C1 | `f095_compiler_opt_constfold_dce_cse` | `DeadCodeElimination::optimize` | `blk=13(foreach_cond_16) then_end=21 ei=12 nce=4 hits=1 first=16(if_then_21)` | 冻结 PASS |
| C1 | `f124_container_orchestrator_pod_service_autoscale` | `ContainerOrchestrator::autoscale` | `blk=4(for_cond_6) then_end=11 ei=2 nce=4 hits=1 first=6(if_then_10)` | 冻结 PASS |
| C1 | `ref002_r1b_isolated_tmp` ×2 | `__closure_2` / `__closure_3` | `blk=3 then_end=9 ei=2 nce=6 hits=1`（first 分别为 `if_then_6`/`if_then_18`） | PASS 探针 |

**逐字段排查（红/绿无一分离）**：`cs18_end == end_idx` 在红绿两侧**全部成立**（不是特征）；`nmi` 落在帧内在红绿两侧亦全部成立；`nce`（链层数 ×2）红 2/2/4 vs 绿 2/2/2/2/4/4/6/6 交叠；`hits` 红 1/1/2 vs 绿 1×7 与 2×1 交叠。⇒ **「臂是否在帧内」本身是正常几何**：有序分支把同帧的 then 与 else 两臂线性发成 `if {…} else {…}` 正是正确形态，红形与该形态在归属口径下**不可区分**。

**C3 / CD 全部零命中**（`C3` 40 读数、`CD` 1 读数，`hits>0` 事件 0）⇒ 形 9 的越界**不在** else 臂循环头派发帧，也不在 `chain_unwind` 单臂帧 ⇒ 行动前的两处猜测（"形 9 落 C3 因 `else_branch_start` 为 null"、"CD 帧需同款收窄"）均被否证。

#### 3.7.3 唯一幸存读数与后继可测问题（改问「臂重联」，不再问「区间」）

C1 侧的红绿差只剩一处，且本轮**未把它设计成判据**：红形 9 `hits=2`（一个链层的 then+else **成对**全在帧内）vs 四个绿事件 `hits=1`（只有一臂在帧内）。探针只计数、未记录"同层配对"，故该读数尚不足以立判据。

代码侧的机制读法（:8604–:8629，本轮只读）：`else_branch_start` 仅在 `else_bi` 终止符为 **`.br`** 时求得（:8611–:8617），若 else 目标本身是链节点（终止符 `.cond_br`，即 elseif）则为 **null** ⇒ `then_end` 落到 `end_idx` 兜底。**红与绿都走这条 null 兜底**（绿形同样 `hits>0`）⇒ 上界求解处不存在可判别的谓词。

⇒ **B/C 的前置问题改写**（待裁决，禁止先写区间代码）：从「哪个块属于本链的臂」改问「**then 臂内完成循环派发之后，本节点的 else 目标还能否被重联成 `} else {`**」。可证伪探针 = 在 `then_indirect_to_else` 的两条出口与 :8646 帧递归出口读 `else_branch_start 是否为 null`、`else_bi` 终止符 tag、`then_end == end_idx` 兜底标志、以及派发后 `merge_bi`/`processed` 对 else 臂的归属；判据成立条件 = 该组读数在红形 9/4/7 与绿形 f095/f124/f080/f067 之间**完全二分**。若二分成立，修法为「循环派发出口**重取**臂上界/臂重联」，而非收窄区间。

#### 3.7.4 本轮判定（写进口径，防复发）

1. **臂归属判据否证**：R5 否证了结构口径（标签前缀 + processed），R6 否证了归属口径（沿 else 目标可达）。**任何以"区间上界"为作用点的 B/C 判据都不可落地** —— 红与绿共享同一区间几何，差异在发射期的臂重联，不在 CFG 的块集合。
2. 形 4/7/9 仍 **OPEN**，且阻塞物已换名：**臂重联判据**（新影子轮 R7），不是臂归属判据。
3. 批次可达终态**不变**（§3.6.5）：A ⇒ `same=5`；A+D ⇒ `same=6`；4/7/9 不计入。

#### 3.7.5 R6 收尾复验（实测，2026-10-04）

| 门 | 读数（还原后 clean 二进制，`zig build rc=0/64s`） | 与 R6 插桩前 |
|---|---|---|
| 门 A（17 形等值） | `PROBE_DONE total=17 same=17 differs=0` | 一致 |
| RC-4 门 | `RC4_PROBE_DONE total=4 same=3 differs=1`（唯一红点 `ref003_crash_attr` 缺 W3 ⇒ 归 REF-003） | 一致 |
| RC-5 八形合串 | `IDENTICAL` | 一致 |
| do-while 门 | `DOWHILE_PROBE_DONE total=2 same=2 differs=0` | 一致 |
| 本单 9 形门 | `C006_TL_GATE_DONE total=9 same=2 differs=7`（绿 2/3；红 1/4/5/6/7/8/9，逐形输出与插桩前一致） | 一致 |

⇒ R6 对发射**逐字节中性**（含探针代次 `drift_ok=68/diff=0` + 还原后五门读数不变）成立；本轮支出为纯取证，工作区与暂存区仍为 RC-5 批次（`+128 / −23`，blob `3ae7b34e`），未提交。

### 3.8 R7 臂重联探针口径设计稿（设计稿撰写时为「未插桩」；**实际已于 2026-10-04 23:19 插桩并开跑，落地记录见 §3.8.6**；设计行号代次 = D 批落地后工作区 blob `9490bf9f`、32663 行）

**命题（由 §3.7.3 改写，不再问区间）**：`then` 臂内完成循环派发之后，本节点的 `else` 目标**还能否被重联成 `} else {`**。R6 已证「块是否在帧内」在红绿两侧不可区分 ⇒ 差异若存在，只可能在**派发出口之后的臂重联条件**上。

#### 3.8.1 站点（三处，均为 `std.debug.print` 写 stderr，禁止经过 `writer`）

| 标签 | 站点（当前代次实测行号） | 帧 | 为什么是这里 |
|---|---|---|---|
| `[S08T1]` | 主 `.cond_br` 处理器 then 帧：`then_end` 求解之后、区间行走之前 `:8737`／行走之后 `:8742` 之后各读一次 | `[blk_i, then_end)` | R6 的 C1 同位点，但 C1 只数了归属块；本轮改读**上界来源与派发后状态** |
| `[S08T2]` | `loop_exit_is_outer_merge` 两条出口：直派 `:8676–:8694` 与区间行走 else 支 `:8695–:8764` | — | 这是 `then_indirect_to_else` 唯一的「循环把臂尾接管」分岔，重联语义在此定形 |
| `[S08T3]` ×2 孪生 | 有序分支上界：第二孪生 `cs18_end` 求解 `:10069` 与递归 `:10081`；第一孪生同位（无上界变量、直接用 `end_idx` 的 `:9521–:9533` 区） | `[nti, cs18_end)` / `[nti, end_idx)` | R6 的 C2 命中面（红 4/7 + 绿 f025/f043/f072/f080/f067 全在此）；**两孪生不对称本身待读**（一有界一无界） |

#### 3.8.2 每次事件必须读的字段（缺项即视为该轮无效）

1. `else_branch_start == null`（仅 `else_bi` 终止符为 `.br` 时非 null，:8698–:8711）
2. `else_bi` 终止符 tag（`.br` / `.cond_br` / 其他）与 `else_block` 标签
3. `then_end` 的来源分支：`@min(ei,end_idx)` / `@min(ebs,end_idx)` / `end_idx` 兜底（:8720–:8737 三条）
4. 派发返回后的 `last_loop_fallthrough_idx`、`lfi_is_join`（:8748–:8760 五条件逐条读，便于定位是哪一条挡住重联）、`merge_bi`
5. else 臂索引及其 `processed` 状态、`instructions.items.len`
6. `return_generated` / `break_generated` 在恢复前是否为真（臂尾不可达放大器）

#### 3.8.3 判据成立 / 否证条件（先写死，防事后凑判据）

- **成立**：上述字段组合在红形 **4 / 7 / 9** 与绿侧 **f095 / f124 / f080 / f067（+ 其余冻结通过脚本）** 之间**完全二分**，且二分组在语料上的命中面能给出可落地谓词（命中脚本集合 ⊆ 已知红形 ⇒ 语料面 0 最理想）。
- **否证**：任一字段在红绿两侧取值交叠 ⇒ 与 R5/R6 同判：**区间与重联两处作用点全部出局**，B/C 的开放前置改记为「需换发射层（`generateIfFromLabels` 复用语义或 IR 层臂规范化）」，并停止在本函数内加判据。
- 本轮**禁止**同时改发射；只出读数。

#### 3.8.4 中性证明与还原复验（沿用 R6 同法，七项）

含探针代次全量漂移必须 `drift_ok=68 drift_diff=0 notemp=0 norow=0 compile_fail=0`；还原后逐项复验：`md5`、行数、`S08` 残留 0、工作区 vs 暂存区差分行 0、暂存仍为 RC-5+A+D 批、blob、`runtime_lib_template.zig` md5 不变；clean 重建后五门读数与插桩前一致（门 A / RC-4 / RC-5 八形 / do-while / 本单 9 形）。

#### 3.8.5 预算与排期约束

覆盖 114 脚本（68 语料 `pass/` + 46 永久探针）串行独占，预计 30–45 分钟；批次期间禁止并发 AOT 编译 ⇒ 与 D 批验收门不可重叠。**待老铁点头后才插桩**（§六：涉发射侧共享语义前置取证）。

#### 3.8.6 R7 插桩落地记录（2026-10-04 23:19 开跑；本轮实测，非设计稿）

**代次校验**：探针代次 `native_linker.zig` md5 `3a7de0a45760cf9935d8124e46bc8634`、**32746 行**（相对 D 批干净树 32663 行 **+83**），`git diff --numstat` = **+206 / −6**（工作区 vs 暂存区，含未暂存的 A+D 批 `+123/−6`）；`timeout 560 zig build` **rc=0**；`runtime_lib_template.zig` 未触碰（md5 `008b7b63…` 不变）；硬备份 `/tmp/nl_backup_9490bf9f.zig`（md5 `fdeebc14…`，32663 行）。

**站点落地（8 处，实测行号属探针代次）**：

| 标签 | 实测行号 | 帧/语义 | 与设计稿差异 |
|---|---|---|---|
| `[S08T2]` | `:8695` | 直派支 `loop_exit_is_outer_merge` 出口（臂尾被循环接管） | 与 §3.8.1 同位（设计写 `:8694`，插桩后行号即打印行） |
| `[S08T1A]` | `:8768` | `then_end` 求解后、帧递归前 | 设计 `:8737`；同位点，行号因前置 `[S08T2]` 插桩而 +31 |
| `[S08T1B]` | `:8776` | 派发返回、`defer_loop_fallthrough` 恢复后 | 设计 `:8742` 之后 |
| `[S08T1C]` | `:8800` | `lfi_is_join` 五条件逐条重算 | 设计 `:8759` 之后 |
| `[S08T3F1]` | `:9583` | 无界孪生 **twin A**（直接用 `end_idx`） | 设计只列一处（`:9521–:9533` 区） |
| `[S08T3F2]` | `:10557` | 无界孪生 **twin B** | **设计稿未发现孪生有两份拷贝**：`grep -n "func, nti, end_idx, cleanup_regs, processed, loop_label_counter, body_indent"` 在探针代次命中 `:9585`/`:10559`（插桩前同 grep 命中 `:9533`/`:10497`），且 `:10566` 注释「与 twin A 对称」自证二者成对 ⇒ 站点 7→8 |
| `[S08T3S1]` | `:10140` | `cs18_end` 求解后（有界孪生）：报 `hdr`（nmi 标签是否循环头前缀）、`nmilbl`、循环上下文 | 同设计 |
| `[S08T3S2]` | `:10152` | 有界孪生递归前：报 `span/unproc/else_in_rng/post_unproc` | 同设计 |

**脚本集口径修正（可复现优先）**：设计 §3.8.5 写「114 = 68 语料 + 46 永久探针」，但 **46 这个数无法从现存树复现**（R6 轮的临时清单脚本按宪法 §三-7 已删除）。本轮把口径改为**自生成、可复现**：语料 `fuzzy_scripts_720/pass/*.php`（68，实测）+「被任一现存门/取证脚本引用且文件存在的 `*_tmp.php`」= `grep -hoE "[a-zA-Z0-9_]+_tmp" fuzzy_scripts_720/tmp/*.sh scripts/*.sh | sort -u` 过滤存在性 ⇒ **45**，合计 **113**。档位沿用各自配方：语料默认 `--compile --no-debug-info`（同时逐行核冻结基线 ⇒ 兼做中性证明），探针 release-fast（与 9 形门/D 门一致）。**红绿比较跨档**是本口径固有局限，判据若仅依赖布尔/索引类字段则不受影响，已在 §3.9 结论处标注。

**聚合缺陷（已修，读数原文未受损）**：扫描脚本的 per-script `sites=` 列用 `grep -oE '\[S08T[0-9A-F]+\]'` 抽标签，字符类缺 `S` ⇒ `S08T3S1`/`S08T3S2` 抽取恒为空（形 4 冒烟即命中此坑：`readings=2 sites=` 空）。`.probes` 原文与末尾 `SITE|` 统计走 `grep -cF "[tag]"` 字面量，**不受影响**；聚合改用 `c006_r7_aggregate_tmp.sh`（标签抽取为字面量）。

**开跑前冒烟（形 4 `c006_tl_elseif_loop_tmp`，release-fast）**：`rc=0`，2 读数 ⇒ `[S08T3S1] nti=4 nmi=6 cs18_end=9 end_idx=9 nmilbl=for_cond_7 hdr=true else_bi=2 merge_bi=3` / `[S08T3S2] span=5 unproc=5 nproc=false else_in_rng=false post_unproc=0`。即 **D 批 `cs18_end` 兜底已生效**（`hdr=true` ⇒ 上界取 `end_idx`），本形仍丢臂 ⇒ 红形的失效点不在「上界截断」，而在「区间外（`else_bi=2 < nti=4`）的臂无人重联」。全量判定见 §3.9。

### 3.9 R7 臂重联判据影子轮实测（2026-10-04 23:19–23:37；113 脚本；发射侧零改动；**判据否证 = 本单第三次**）

**轮次账（全部实测）**：插桩 8 站点（§3.8.6，md5 `3a7de0a4…`、32746 行、+83）→ `timeout 560 zig build` `rc=0` → 串行扫描 `23:19:10 → 23:36:53`（**17m43s / 113 脚本 ⇒ 9.4s/脚本**）→ **`R7_DONE total=113 corpus=68 probe=45 hits=41 drift_ok=68 drift_diff=0 notemp=0 norow=0 compile_fail=1`** ⇒ 含探针代次对 68 条冻结基线**逐字节中性**（`drift_diff=0`），唯一 `compile_fail` = `ref_semantics_matrix_probe_tmp`（rc=1，见 §3.9.4 归因）→ 还原 7 项全等 + clean 重建 `rc=0 / 73s`（§3.9.4）。

#### 3.9.1 站点命中面：命题指定的两处作用点在红形上**一次都没触发**

| 标签 | 读数 | 脚本 | 红形命中 | 绿侧命中（节选） |
|---|---|---|---|---|
| `[S08T1A]` | 15 | 11 | 仅形 9 | f051/f056/f067/f095/f102/f124/f177 + ref002_r1b/ref003_liveset/ref_iter |
| `[S08T1B]` | 15 | 11 | 仅形 9 | 同上（A/B 恒成对） |
| `[S08T1C]` | 10 | 7 | **0** | f051/f056/f095/f102/f124 + ref002_r1b/ref_iter |
| `[S08T2]` | 1 | 1 | **0** | 唯一命中 = 绿语料 f067（直派出口 `tlabel=while_cond_11 else_bi=merge_bi=10`） |
| `[S08T3F1]` | 1 | 1 | 0 | f080（绿） |
| `[S08T3F2]` | 21 | 18 | 0 | f024/f027/f032/f033/f036/f043/f067/f095/f105/f113/f117/f124/f134/f135/f160/f161/f178（全绿） |
| `[S08T3S1]` | 26 | 22 | 形 4、形 7 | 20 条绿语料/探针 |
| `[S08T3S2]` | 26 | 22 | 形 4、形 7 | 同上 |

**两条结构性事实（先于判据）**：
1. **红族覆盖率仅 3/7**：九形门 9 个脚本全部进入扫描（`list_probe` 实测 `IN` 9/9，另有 `c006_tl_two_elseif_{early,then}` 共 11 个 c006 文件），但只有形 4/7/9 产生读数；红形 **1/5/6/8** 与绿形 **2/3** 在 8 站点上**零读数** ⇒ 本探针组对红族的机制根本不覆盖。
2. **命中的站点不是命题站点**：形 4/7 只命中**有界孪生** `[S08T3S1/S2]`，其语义是「嵌套 if 的 `nti` 与上界 `cs18_end`」；§3.8 命题要读的「`then` 臂派发出口之后的臂重联条件」位于 `[S08T2]`/`[S08T1C]`，二者在三个红形上全零 ⇒ 红形的失臂发生在**进入重联逻辑之前**，不在重联条件上。

#### 3.9.2 红形全读数 × 绿侧同组合计数（交叠即否证）

```text
形4 c006_tl_elseif_loop_tmp
[S08T3S1] nti=4 nmi=6 cs18_end=9 end_idx=9 nmilbl=for_cond_7 hdr=true else_bi=2 merge_bi=3 loopcond=null loopexit=null looplbl=null
[S08T3S2] nti=4 cs18_end=9 span=5 unproc=5 nproc=false else_in_rng=false post_unproc=0 else_bi=2 end_idx=9
形7 c006_tl_fncontext_loop_tmp
[S08T3S1] nti=3 nmi=5 cs18_end=8 end_idx=8 nmilbl=for_cond_7 hdr=true else_bi=2 merge_bi=null loopcond=null loopexit=null looplbl=null
[S08T3S2] nti=3 cs18_end=8 span=5 unproc=5 nproc=false else_in_rng=false post_unproc=0 else_bi=2 end_idx=8
形9 c006_tl_ifarm_loop_tmp
[S08T1A] ti=1 blk_i=4 end_idx=9 then_end=9 src=end_idx_null ebs=null etag=cond_br else_bi=2 elab=if_else_1 eproc=false einst=3 else_in_rng=false thenlbl=if_then_0
[S08T1B] ti=1 blk_i=4 then_end=9 lfi=null lsrc=null merge_bi=null rg=false bg=false saved_df=false df=false
```

| 红形 | 谓词组合（去掉尺寸类字段） | 绿侧同组合读数（复测口径：按读数与去重脚本分别计数） |
|---|---|---|
| 形 4 / 形 7 | `else_in_rng=false, post_unproc=0, nproc=false, cs18_end==end_idx` | **18 条读数 / 16 个不同绿脚本**：f007、f025、f026、f031、f032、f043、f067、f067_min_repro、f072、f080、f102、f124、f160、f163、f173、f179 |
| 形 9 | `src=end_idx_null, ebs=null, etag=cond_br, eproc=false, else_in_rng=false` | `S08T1A` 15 条读数中该 5 元组共 **7 条 ⇒ 红 1 + 通过脚本 6**（f095、f124、ref_iter_slot_stale、ref003_liveset_bisect、ref002_r1b_isolated×2）；其中 ref002_r1b 的两条与红形 9 **仅 `blk_i` 不同**（3 vs 4），`else_bi=2/einst=3` 全同 |
| 全部红形 | `[S08T1C]` 五条件 | 无红形读数；绿侧 8 条 `join=true` + 2 条 `c3=false⇒join=false` |

⇒ 每个红形的取值组合都在**通过脚本**上重现 ⇒ §3.8.3 判据成立条件不满足。

#### 3.9.3 构造性失效（比 R5/R6 更强的否证证据）

`else_in_rng` 在携带该字段的孪生读数中 **47/47 恒为 false**；`else_bi < nti` 在**全部 48 条**孪生读数中 **48/48 成立**（`S08T3S1` 26/26、`S08T3S2` 26/26、`S08T3F1` 1/1、`S08T3F2` 21/21）。根因不是形态差异，而是**节点错配**：孪生站点处的 `else_bi` 是**外层** `cond_br` 的 else 目标，`nti` 是**嵌套 if** 的 then 块，而本 IR 的块序恒把外层 else 臂排在嵌套 then 之前（观测到 `else_bi = nti − 1` / `nti − 2` 恒成立）⇒ 该字段**按构造恒定，不可能二分**。这是一条自否证：R7 的探针有一半装在了与命题不同层的节点上。

⇒ **触发 §3.8.3 预登记否证条款**（原文：任一字段在红绿两侧取值交叠 ⇒ 与 R5/R6 同判：区间与重联两处作用点全部出局，B/C 的开放前置改记为「需换发射层」，并停止在本函数内加判据）。

**三连否证的合取结论**：R5（区间收紧 PB/PC/PD）+ R6（CFG 指针归属）+ R7（派发后臂重联）在 113 脚本红绿面上**均不可判别** ⇒ `generateLabelDrivenBlockRange` 内的「区间上界 / 块归属 / 臂重联」三类判据**搜索已穷尽**；R7 额外给出正向定位：红形 4/7/9 的失臂点**在进入 `loop_exit_is_outer_merge` 直派出口与 `lfi_is_join` 重联之前**（这两处在红形上零触发），且 D 批 `cs18_end` 循环头兜底已生效（`hdr=true ⇒ cs18_end==end_idx`）却仍丢臂 ⇒ 剩余唯一可行方向是**发射层之外**（链臂一次性双臂发射的 D 类扩展，或 IR 层臂规范化），本函数内不再加判据。**（同句就地更正，2026-10-04 §3.10：「发射层之外」推论作废 —— 生成码侧证明缺失点在发射层**之内**的内联发射器 terminator 分派，臂并未真丢；本段的否证部分（三类判据穷尽）仍然有效。）**

#### 3.9.4 还原复验、clean 重建、门读数与 compile_fail 归因

**还原七项复验（实测，2026-10-04 23:47 前后，全部与探针前基线全等）**：

| 项 | 探针代次 | 还原后实测 | 判定 |
|---|---|---|---|
| `native_linker.zig` md5 | `3a7de0a45760cf9935d8124e46bc8634` | `fdeebc14daa456bb94437345ab771697` | 等于 D 批工作区态 ✓ |
| 行数 | 32746 | 32663 | −83（探针净增量）✓ |
| 探针残留 | 8 站点 | `grep -cF 'S08T'` = **0** | ✓ |
| 工作区 vs HEAD | `+206/−6` | **`+123/−6`** | 等于 A+D 基线 ✓ |
| 暂存区 vs HEAD | `+128/−23` | **`+128/−23`**（blob `3ae7b34e`） | 未受本轮影响 ✓ |
| `runtime_lib_template.zig` | 未触碰 | `git diff` 无该文件条目 | ✓ |
| 备份一致性 | `/tmp/nl_backup_9490bf9f.zig` | 还原即自该备份回写 | ✓ |

**clean 重建**：删除 `zig-out`/`.zig-cache` 后 `timeout 560 zig build` ⇒ `CLEAN_BUILD_RC=0`，耗时 **73s**。

**六门复跑（串行、同一 release-fast + `--no-debug-info` 档，逐门等于 A+D 基线）**：

| 门 | 命令 | 实测读数 | 与基线 |
|---|---|---|---|
| 等值门（17 形） | `c005_probe_run_tmp.sh` | `PROBE_DONE total=17 same=17 differs=0` | 全等 |
| RC-4 门 | `c005_rc4_probe_run_tmp.sh` | `RC4_PROBE_DONE total=4 same=3 differs=1` | 全等（唯一红点仍 `ref003_crash_attr_tmp`，W3 `grow-then-continue` 缺失 ⇒ 归 **REF-003**，不属本单） |
| RC-5 门 | `c005_rc5_probe_run_tmp.sh` | `IDENTICAL\|c005_rc5_merge_loss_tmp\|rc=0` + `RC5_PROBE_DONE file=c005_rc5_merge_loss_tmp` | 全等 |
| do-while 门 | `c005_dowhile_probe_run_tmp.sh` | `DOWHILE_PROBE_DONE total=2 same=2 differs=0` | 全等 |
| 本单 9 形门 | `c006_tl_probe_run_tmp.sh` | `C006_TL_GATE_DONE total=9 same=6 differs=3`（红 = 形 4/7/9） | 全等（形 8 保持绿） |
| D 旁门 | `c006_d_probe_run_tmp.sh` | `C006_D_GATE_DONE total=2 same=2 differs=0` | 全等 |

**`compile_fail=1` 归因（`ref_semantics_matrix_probe_tmp`）**：还原后的干净树上同档复跑，报 `error: executable generation failed: CompilationFailed / 2 error(s) generated` ⇒ 该失败**与 R7 探针无关**（探针只写 stderr，不经 `writer`），属该 REF 系探针自身生成码不可编译的既有状态；R7 期间该脚本对冻结基线**无可比对行**（基线 72 行数据中不含它），故 `drift_ok=68 drift_diff=0` 仍成立。不并入本单修复面，登记给 REF-003 复测队列。

**本轮支出**：插桩 → build → 113 脚本扫描（17m43s）→ 还原 + clean 重建（73s）+ 六门复跑 ⇒ 发射侧零改动、工作区回到 A+D 未暂存态，结论为**否证**（§3.9.3）。

### 3.10 R8 前置：生成码结构取证（只读、无插桩；2026-10-04 实测）—— 剩余三形重定性为「臂守卫坍缩」

R7 否证后改用**发射结果侧**取证（不进发射器），口径：`ZIGPHP_AOT_KEEP_TEMP=1 timeout 300 zig-out/bin/php-interpreter --compile --optimize=release-fast --no-debug-info`，取 `main.zig` 读函数体控制流（形 9 构建目录 `.zigphp_aot_build_59742`，`__main__` = :36–:439，全文 1510 行；形 4 = `.zigphp_aot_build_59802`）。**注**：读生成码只证「发射结果形态」，不证「哪个站点发出」（流程规约 (c)），故本节仅用于重定性症状与框定 R8 探针该问什么。

**形 9（`c006_tl_ifarm_loop_tmp`，`$mode="1"`）实测结构**：

```text
main.zig:119  reg_3 = php_identical($mode, "1")
main.zig:120  if (reg_3.toBool()) {          ← 链首 cond_br 的守卫在（:8485 那条 print 走了正常路径）
main.zig:121  …php:8–14（if 臂体 + __for_0 循环 + echo "T9 hit=…sum=…"）
main.zig:310  …php:16（elseif 臂体 echo "T9 b2"）      ← 无任何 if 守卫，直落
main.zig:358  …php:18（else 臂体 echo "T9 else"）      ← 无任何 if 守卫，直落
main.zig:406  } else {
main.zig:407  …php:15（$mode 装载 + reg_29 = php_identical(...)，即 elseif 的**条件块**）
main.zig:418  }                                ← reg_29 算完即弃，全文再无 if (reg_29…)
```

实测计数：`if (reg` 形态在 `__main__`（:36–:439）体内**仅 1 处**（`:120`，即链首守卫；全文件另有 1 处命中在 `:1027` 的 `aot_function_exists` helper，与本函数无关）；elseif 的条件计算结果 `reg_29` 在生成码里除末尾 `release` 外**无任何消费者**（实测 `:417` 赋值，其余 6 处均为 `release`/置 null）。⇒ 运行输出 = 三臂顺序全执行（`T9 hit=3 sum=3 / T9 b2 / T9 else`），与门里 `DIFF|…|aot=[T9 hit=3 sum=3 T9 b2 T9 else ]` 逐字对应。

**形 4（`c006_tl_elseif_loop_tmp`，`$mode="2"`）实测结构**：

```text
main.zig:123  reg_3 = php_identical($mode, "1")
main.zig:124  if (reg_3.toBool()) {  …php:8 echo "T4 branch1"  }   ← then 臂正常（本例不取）
main.zig:175  } else {
main.zig:184  reg_7 = php_identical($mode, "2")   ← elseif 条件块：只发指令，无守卫
main.zig:~197 …php:10–13（elseif 臂的 $hit/$sum/$i 初始化，直落）
main.zig:213  …php:18 echo "T4 else"（**else 臂体排在 elseif 臂体之前**）
main.zig:257  __for_0: while (true) { … }          ← php:12–15 循环
main.zig:386  …php:16 echo "T4 hit=…sum=…"
```

实测计数：该函数体内 `if (reg` 同样**只有链首 1 处**（`:124`；全文件另一处命中在 `:1040` 的 helper）；`reg_7` 在生成码中除赋值与末尾 `release` 外**无消费者**（`grep -n 'reg_7'` = 声明 2 行 + 各清理块 + `:184` 赋值 + `:449` release）。⇒ 运行输出 `T4 else / T4 hit=3 sum=3`（顺序错、臂互斥丧失），与门读数逐字对应。

**证据边界（先声明，防越界结论）**：本轮只取了 **形 9 与形 4** 的生成码；**形 7 未取码**，其唯一实测为门读数 `DIFF|c006_tl_fncontext_loop_tmp|php=[T7 hit=3 sum=3 ]|aot=[T7 branch3 ]`（输出为链首臂 ⇒ **取错臂**，且未见其余臂体）。所以下述第 1 条对 **4/9** 是实测结论，对 **7** 仅是「与 4 同站点族」的待证假设，须由 R8 用同一取码法复证。**（R8 已复证归属，2026-10-05 §3.11：形 7 在同一 `S09I` 站点读得与形 4 同判据的读数 ⇒ "同站点族"假设成立；形 7 的生成码侧仍未取，属遗留复测项，不影响归属结论。）**

**重定性（写入口径，防复发）**：

1. **形 4/9** 的剩余症状**不是「臂丢失」**（臂体一块没少，三条臂全在码里），而是 **「链第二级 `cond_br` 的终止符未被派发」⇒ 守卫缺失 ⇒ 兄弟臂被按块序线性摊平**；**形 7** 为同族的另一种表现（取错臂，码侧未证）。本单标题与 §4 的「四类后果 = 四处缺失派发」中的「末臂整块丢失」只适用于形 1/5/6/8；对 4/9（及待证的 7）必须改记为 **arm guard collapse（臂守卫坍缩）**。
2. 关键反证：**`.cond_br` 行内处理器进入即无条件 `try writer.print("{s}if (", .{indent})`（当前代次实测 `:8485`，先于 `writeConditionExpr` `:8486`）**。⇒ **本条的推论部分已被 R8 插桩否证（2026-10-04，§3.11）**：原写「形 4/9 的 elseif 条件块就从未进过该处理器、其指令由只发指令不发终止符的内联发射器写出」不成立 —— else 臂经 `emitBlockInlinedWithPhiFrom`（`:9761`）内联后，其终止符 switch（`:9763`）**确有 `.cond_br => |nested_cb|` 分支（`:9851`）**，条件块**进了**处理器；坍缩发生在**处理器内部的路由选择**（兜底分支对 `[nti, cs18_end)` 做线性摊平、不发守卫）与**臂块被前帧提前消费**（守卫分支因 `processed.contains(nti)` 整体跳过）两点，实测读数与站点见 §3.11。原列举的 `:7225–:7228`/`:7264–:7268`/`:7272–:7276` 三个「只看 `.br`」候选站点在红三形上**均未成为坍缩源**（R8 探针 `S09B` 在 `:8466` 的"两目标已处理即跳过守卫"逃逸也**零触发**）。
3. ~~由此，R8 应问的唯一问题：内联发射器能否识别 `.cond_br` 目标块并交回主行走。~~ **R8 实测改问法（§3.11）**：问「`nested .cond_br` 处理器在**已收到**该块时，为什么把双臂摊平而不是发守卫」——答案由两条独立路由读数给出（形 4/7 = 兜底线性摊平；形 9 = 前帧越界吞臂后守卫分支被 `processed` 短路）。

⇒ §4 的 B/C 两行按本节的**发射结果侧证据**重述，R7 的「发射层之外」推论作废（真实方向是**发射层之内的内联发射器 terminator 盲区**，仍是本函数族内，但不属 R5/R6/R7 试过的三类判据）。

### 3.11 R8 插桩取证轮（2026-10-05 实测；stderr-only、发射侧零行为改动、可完全还原）

**代次戳（规约 (b)）**：干净树 = D 批 `9490bf9f`/32663 行（工作区 md5 `fdeebc14daa456bb94437345ab771697`）；插桩代次 md5 `24b41b37be85c37f2ba3e0327192b5ec`/32710 行（`+47/−0`，全为 `std.debug.print`，无一字进 `writer`）。探针站点与还原用备份 `/tmp/nl_backup_9490bf9f_r8.zig`。

**七枚探针（tag → 站点，插桩代次行号）**：

| tag | 站点 | 读什么 |
|---|---|---|
| `S09E` | `:7331` `generateLabelDrivenBlockRange` 帧入口 | `start`/`end`/起始块标签 |
| `S09F` | `:7372` 行走器 `for_cond_` 派发 | 标签 + 本帧 `i`/`end`/`range_start` |
| `S09L` | `:8356` 「普通线性块」路径（`processed.put(i)` 之后） | 块索引 + 标签 + `@tagName(terminator)` + 本帧区间 |
| `S09B` | `:8482` 行走器 `.cond_br` 的「两目标已处理 ⇒ `break` 交还上层」逃逸 | 源块/两目标标签与索引 + processed 位 |
| `S09H` | `:8764` then 臂尾循环派发帧（`generateLabelDrivenBlockRange(blk_i, then_end)` 之前） | `blk_i`/`else_bi`/`else_branch_start`/`then_end`/`end` |
| `S09I` | `:10107` else 臂行内嵌套 `.cond_br` 的**兜底线性摊平**调用前 | `nti` 与两臂标签、`nmi` 及其标签、`cs18_end`、`end`、两臂 processed 位、`nloop`（`nmi` 是否窄四前缀循环头） |
| `S09D` | `:1009` A 批 helper `dispatchArmTailBrIntoLoop` 窄循环头命中 | `ti`/标签/`end`/缩进 |

**红三形 + 绿控读数（单形串行，`--compile --no-debug-info`）**：

| 形状 | 触发 tag | 读数（逐字） |
|---|---|---|
| 形 4 `c006_tl_elseif_loop_tmp` | `S09I` | `src=entry nti=4(if_then_3) nelse=if_else_4 nmi=6(for_cond_7) cs18_end=9 end=9 tproc=0 eproc=0 nloop=1` |
| 形 7 `c006_tl_fncontext_loop_tmp` | `S09I` | `src=entry nti=3(if_then_3) nelse=if_else_4 nmi=5(for_cond_7) cs18_end=8 end=8 tproc=0 eproc=0 nloop=1` |
| 形 9 `c006_tl_ifarm_loop_tmp` | `S09H` + `S09L` | `src=entry blk_i=4 else_bi=2 ebs=null then_end=9 end=9` ⇒ 同帧 `S09L i=7 lbl=if_then_8 term=br start=4 end=9`、`S09L i=8 lbl=if_else_9 term=br start=4 end=9` |
| 绿控 `c006_tl_ifelse_loop_tmp` / `c006_tl_else_echo_tmp` | —— | 两站点**零读数**（`S09H`/`S09I`/`S09B`/`S09D` 全无） |

**由读数得到的两条独立坍缩路由（均为实测，非推断）**：

- **路由一（形 4/7）＝处理器内部选了「不发守卫」的兜底分支**。`S09I` 站点即 `:10083 else if (nested_then_idx) |nti| { if (!processed.contains(nti)) { … } }` 的第二出口：`nmi >= nti` 且 `nmi` 标签命中窄四前缀 ⇒ `cs18_end` 兜底为 `end_idx`（f161 xp5 修复的原意）⇒ 直接 `generateLabelDrivenBlockRange(nti, cs18_end)` 平铺。**两臂当时都未被消费（`tproc=0 eproc=0`）⇒ 是"能发而没发"**。同函数内的正确模板已在码里：`:10104` 起的「Out-of-order」分支会 `print("if (")` + 内联 then 臂 + `} else {` + 内联 else 臂，且两臂臂尾各调 `dispatchArmTailBrIntoLoop`（`:10166`/`:10210`）。⇒ **形 4/7 的修法 = 把这条路由改到既有双臂模板，不新写机制**（DRY）。
- **路由二（形 9）＝前帧越界吞掉兄弟臂后，守卫分支被 `processed` 短路**。`:8742–:8758` 的 `then_end` 在 `else_bi(2) < blk_i(4)` 且 `else_branch_start=null` 时兜底 `end_idx(9)`，于是 `[4,9)` 帧把 if/else 链第二级的两臂块（7/8）平铺消费；随后 else 臂的嵌套 `.cond_br` 处理器因 `!processed.contains(nti)` 不成立**整体跳过**（`S09I` 因此零读数，与 §3.10「连 `if (` 都没有」的生成码侧观察一致）。⇒ **形 9 的修法 = 收帧上界，且必须避开 R5 否证的「以 `else_bi` 为界」**（此处 `else_bi < blk_i`，用它即得空区间）。

**否证项（写死，防复发）**：① `:8466` 的"两目标已处理 ⇒ 不发守卫"逃逸（`S09B`）在红三形与全量 105 脚本上**零触发**（语料 0 行、探针 0 行），不是坍缩源；② A 批 helper（`S09D`）在红三形上**零触发**（其 4 次触发全落在绿形：`c006_tl_shape1`/`_else_while`/`_else_loop_tail`/`perf001`）⇒ 形 9 的臂尾循环走的是 `:8662/:8764` 的老内联派发路径，A 批四处站点覆盖不到本族；③ `generateIfFromLabels`（R1 已证 0 命中）在本轮仍不参与。

**候选落地判据（触发条件先写死，语料命中面 = 全量影子轮已回填，见下表末列）**：

| 编号 | 触发（全部为已打印字段） | 落地动作 | 全量影子轮实测面（68 语料 + 37 探针，02:34–02:46/03:0x） |
|---|---|---|---|
| R8-a（形 4/7） | `S09I` 且 `nloop=1` **且** `nelse` 前缀 `= if_else_` **且** `tproc=0` **且** `eproc=0` | 改走 `:10104` 既有「Out-of-order」双臂模板（不发线性摊平） | **语料面 = 1 事件（非零，原口径不可落地）**：`f067_json_parser_schema_path_diff` `src=params_merge nti=6(if_then_2) nelse=if_else_3 nmi=9(foreach_cond_5) cs18_end=26 end=26 tproc=0 eproc=0 nloop=1`。`S09I` 全量：语料 23 行 / 19 脚本，`nelse` 分布 = `if_merge_`×12、`coalesce_merge_`×6、`ternary_else_`×3、`if_else_`×2（f067 + f080，后者 `nloop=0` 被排除）；`nloop=1` 共 7 事件（f007/f026/f067/f067_min_repro/f102×2/f124）。探针面 = 2 事件（形 4、形 7），与语料 f067 事件字段同构 ⇒ **必须再收紧，否则 f067 变红** |
| R8-b（形 9） | `S09H` 且 `then_end == end` **且** `else_bi < blk_i` **且** `ebs = null` **且**（else 块自身为 `.cond_br` 且两目标索引均 `> blk_i`） | 帧上界收为该 else 块 `cond_br` 两目标索引的最小值（兄弟臂子树起点），使臂块留到守卫分支发射 | **语料面 = 4 事件（前四项，非零）**：f056 `blk_i=3 else_bi=2 ebs=null then_end=6 end=6`、f095 `blk_i=13 else_bi=12 … then_end=21 end=21`、f102 `blk_i=3 else_bi=2 … then_end=8 end=8`、f124 `blk_i=4 else_bi=2 … then_end=11 end=11`（f124 与形 9 `blk_i=4 else_bi=2 then_end=9 end=9` **前四项逐字段同构**）。`S09H` 全量：语料 9 行 / 6 脚本，其中 `then_end==end` 6 行；末项条件（else 块 terminator 形态与其 `cond_br` 两目标索引）本轮探针未打印 ⇒ **不可凭前四项改，须 R8.1 窄面复测** |
| R8-c（未成立） | 「内联发射器遇 `.cond_br` 目标块交回主行走」 | —— | §3.10 第 2/3 条原设想，被本轮 `S09B` 零触发否证（语料 0 行、探针 0 行），**出局**；`S09D`（A 批 helper）语料 0 行、探针 4 行且全落在绿形（`c006_tl_shape1`/`_else_while`/`_else_loop_tail`/`perf001`），红三形 0 行 ⇒ 否证项 ② 仍成立 |

**全量影子轮回填（实测，2026-10-05）**：`S09_SHADOW_DONE total=105 corpus=68 hit_scripts=102 compile_fail=0 drift_ok=68 drift_diff=0 drift_notemp=0 drift_norow=0` ⇒ **插桩代次对 68 语料逐字节中性**（默认 `--compile --no-debug-info` 档），七枚探针的读数可用于路由判定。逐 tag 总量：`S09B` 0/0；`S09D` 语料 0、探针 4；`S09E` 语料 1541 行/62 脚本、探针 206/35；`S09F` 语料 118/28、探针 44/27；`S09H` 语料 9/6、探针 1/1（形 9）；`S09I` 语料 23/19、探针 2/2（形 4/7）；`S09L` 语料 926/62、探针 75/35，其中症状面（`lbl=if_then_/if_else_`）语料 14 行、探针 11 行。

**症状面读数给出的新判别线索（本轮已收集字段，可直接复核）**：把 `S09L` 的 `start` 与 `S09I`/`S09H` 的帧起点对照，可区分「臂块被本帧线性吞掉」与「臂块由自己的守卫帧发射」：

- 形 4：`S09L i=4 lbl=if_then_3 term=br start=4 end=9` + `i=5 lbl=if_else_4 term=br start=4 end=9` ⇒ 两臂块都由平铺帧 `[4,9)` 吞（`start == nti`）。
- 形 7：`S09L i=3 lbl=if_then_3 term=ret start=3 end=8` ⇒ 同帧吞臂。
- 形 9：`S09L i=7 lbl=if_then_8 … start=4 end=9`、`i=8 lbl=if_else_9 … start=4 end=9` ⇒ 由 `S09H` 帧 `[4,9)` 吞（`start == blk_i`）。
- 绿语料 f067：else 臂块 `i=7 lbl=if_else_3 term=cond_br start=7 end=8` ⇒ **自带守卫帧发射**，未被 `[6,26)` 平铺帧吞。
- 绿语料 f102 / f124：臂块读数 `start=10/11`、`start=7`（均 `== i`，即自帧），且都不在对应 `S09H` 帧的 `start` 上 ⇒ 未被吞。

⇒ **R8.1 的窄面复测问题（唯一）**：发射点上「本帧 `[起点, 上界)` 是否真的线性消费了属于本 `cond_br` 链的臂块」能否用可静态求值的判据表达（候选：臂块索引 ∈ (起点, 上界) **且** 该臂块的帧起点等于本帧起点 **且** 本链 else 目标块自身为 `.cond_br` 且两目标索引 > 起点）。需补打印字段：`S09I` 加 `nei`（else 块索引）+ 两臂 `terminator` 标签与 `.br` 目标索引 + `narm`（区间内 `if_then_/if_else_` 块数）；`S09H` 站点加 `S09M`（else 块 `terminator` 标签 + 其 `cond_br` 两目标索引）。复测集 = 形 4/7/9 + f056/f067/f095/f102/f124 + `nloop=1` 其余语料（f007/f026/f067_min_repro）+ 绿控（f080/f087/f161），**不开全量**（语料面已由本轮锁定为「候选冲突脚本 = 5」）。

**硬要求（不变，复算后仍成立）**：R8-a/R8-b 的语料命中面必须为 **0** 且漂移门 `diff=0` 才允许落地；漂移门本轮 `diff=0` 已过；命中面 R8-a=1、R8-b=4 ⇒ **原口径禁止落地**，转入 R8.1 收紧；若 R8.1 仍找不到把红三形与上述冲突脚本二分的判据 ⇒ 4/7/9 按 §7 转结构性长期项（不得以「先落地再回归」绕过）。

### 3.12 R8.1 窄化收紧轮实测（2026-10-05；S09N/S09M 两枚新探针；stderr-only、发射零改动；**结论 = 区间/计数判据第四次否证**）

**代次戳（规约 (b)）**：R8.1 插桩代次 md5 `4f29ae2d54424022ae251bdbeff768e7`、32792 行（相对干净代次 `9490bf9f`/32663 行 `+129/−0`，新增两枚 `std.debug.print` 块，无一字进 `writer`）。扫描：`r81_narrow_scan_tmp.sh` ⇒ `R81_DONE total=73 corpus=68 read_scripts=27 compile_fail=0 drift_ok=68 drift_diff=0 drift_notemp=0` ⇒ **新探针同样逐字节中性**（漂移门第二轮 `diff=0`）。

**新探针字段**：`S09N`（`S09I` 同站点第二行）= `nei`（本链 else 臂块索引）、`ttag/ttgt`（帧起点块 = then 臂的终止符标签与其 `.br` 目标索引）、`etag/etgt`（else 臂块终止符标签与目标）、`narm`（`[nti, cs18_end)` 内 `if_then_/if_else_` 标签块数）；`S09M`（`S09H` 同站点第二行）= `ebi/elbl`（else 目标块）、`etag`、`ethen/eels`（其 `cond_br` 两目标索引）、`ebtgt`（其 `.br` 目标）、`narm`（`(blk_i, then_end)` 内臂块数）。

**红三形逐字读数**：

```text
形 4  [S09I] src=entry nti=4(if_then_3) nelse=if_else_4 nmi=6(for_cond_7) cs18_end=9 end=9 tproc=0 eproc=0 nloop=1
      [S09N] src=entry nti=4 nei=5 nmi=6 cs18_end=9 end=9 ttag=br ttgt=6 etag=br etgt=3 narm=2
形 7  [S09I] src=entry nti=3(if_then_3) nelse=if_else_4 nmi=5(for_cond_7) cs18_end=8 end=8 tproc=0 eproc=0 nloop=1
      [S09N] src=entry nti=3 nei=4 nmi=5 cs18_end=8 end=8 ttag=ret ttgt=99999 etag=br etgt=5 narm=2
形 9  [S09H] src=entry blk_i=4 else_bi=2 ebs=null then_end=9 end=9
      [S09M] src=entry blk_i=4 ebi=2 elbl=if_else_1 etag=cond_br ethen=7 eels=8 ebtgt=99999 narm=2 then_end=9 end=9
```

**语料候选读数（冲突面逐字）**：

```text
f067 [S09N] src=params_merge nti=6 nei=7 nmi=9 cs18_end=26 end=26 ttag=br ttgt=9 etag=cond_br etgt=99999 narm=10
f080 [S09I] src=entry nti=3(if_then_2) nelse=if_else_3 nmi=5(if_merge_4) cs18_end=6 end=6 tproc=0 eproc=0 nloop=0
     [S09N] src=entry nti=3 nei=4 nmi=5 cs18_end=6 end=6 ttag=br ttgt=5 etag=br etgt=5 narm=2
f095 [S09M] src=logical_merge_13 blk_i=13 ebi=12 elbl=if_merge_15 etag=cond_br ethen=16 eels=17 narm=1 then_end=21 end=21
f124 [S09M] src=entry blk_i=4 ebi=2 elbl=if_else_3 etag=cond_br ethen=6 eels=7 narm=1 then_end=11 end=11
f102 [S09M] src=entry blk_i=3 ebi=2 elbl=if_merge_1 etag=ret narm=1 then_end=8 end=8
f056 [S09M] src=entry blk_i=3 ebi=2 elbl=if_merge_1 etag=ret narm=0 then_end=6 end=6
```

**四类候选判据的实测面（`S09N` 语料 24 事件 / 探针 2 事件；`S09M` 语料 9 事件 / 探针 1 事件）**：

| 候选 | 定义 | 覆盖红形 | 语料面 | 结论 |
|---|---|---|---|---|
| P-a1 | `nloop=1 ∧ nelse=if_else_` | 4、7 | 2（f067、f080） | 否证（R8 原口径复现） |
| P-a2 | P-a1 `∧ etag=br ∧ etgt < nti` | **仅 4**（形 7 的 `etgt=5 > nti=3`） | **0**（f067 为 `etag=cond_br`、f080 为 `nloop=0`） | 面为 0 但**只覆盖三形之一**，且可比语料事件仅 2 例 ⇒ 证据面过窄，不构成本族修法 |
| P-cnt | `narm >= 2`（帧内臂块计数） | 4、7、9 | `S09N` 面 = 2（f067 `narm=10`、f080 `narm=2`）；`S09M` 面 = 0 | **否证**（N 侧）；M 侧虽面为 0，但 f124 与形 9 的差别只在「两臂块中其一标签前缀是否 `if_then_/if_else_`」（`ethen/eels` 两目标均 `> blk_i` 且都在帧内，f124 完全同构）⇒ **计数阈值是巧合而非不变量**，禁止作为编译器落地依据 |
| P-bound | 帧上界（`then_end`/`cs18_end`）相关任意合取 | — | — | 与 R5/R6/R7 同层，已被三轮否证 + 本轮再否证 |
| P-背（字段单独面，复核用） | 仅 `etag=br ∧ etgt < nti`（**不带** `nloop`/`nelse` 合取） | 形 4 | **4 事件 = f032（`etgt=5 < nti=6`）、f070（`6<7`）、f124（`3<6`）、f163（`3<6`），四者均为通过脚本** | ⇒ 「else 臂尾反向落到帧起点之前」这一事实本身在 4 个绿语料上成立 ⇒ 该字段**单独不可用**；P-a2 的 0 面完全靠 `nloop=1 ∧ nelse=if_else_` 两枚合取撑住，而这两枚与红/绿无因果（f080 同前缀、只差 `nloop=0`）⇒ **属对红形的拟合而非机制不变量，禁止据此落地** |

**本轮得到的机制级结论（写入口径，防第五次同层试错）**：三红形与 f067/f124/f080 的**全部静态字段（块序、区间、归属、计数、臂尾目标方向）都不能二分**；真正的差异是**行走器在帧内何时停住**（形 4/7/9 的臂尾 `br` 回落到**排在帧起点之前**的链 merge ⇒ 帧内无停止站点 ⇒ 继续线性吞臂；f067/f124 的对应臂尾落到帧内可达 merge ⇒ 帧在那里收口 ⇒ 兄弟臂交回外层守卫发射）。"帧在何处收口"是**行走运行时性质**，不是发射前可求值的区间判据 ⇒ **本族的修复必须在「臂集合 + merge 归属」这一结构层，而不在任何帧上界/计数判据层**。可落地的结构性候选（均属发射侧共享语义，须 §7 裁决）：

1. **链级双臂显式发射**（改动最小但覆盖面待定）：`.cond_br` 处理器遇到「then/else 两臂的臂尾均 `br` 到同一块 `m` 且 `m <` 帧起点」时，改由 `emitChainUnwindArmPair`（`:1035`，干净代次 `9490bf9f` re-grep 实测）发 `if(c){then}else{else}`，两臂各自递归发射后**以 `m` 为 merge 交回外层**（现站点只按 `nmi` 的求解结果选路，而 `nmi` 在乱序链上会误取臂内循环头）。**⚠ 本条谓词的字面写法已被逐字读数否证（红三形两臂尾目标并不相同），更正口径与覆盖面见 §3.13，禁止按原文落地。**
2. **链 arms/merge 归属结构层**（唯一有可证定义支撑，**推荐**，分两条子路线）：
   - **2′ 发射前只读建表（推荐先做）**：linker 内为每个函数一次性构造 `chain_id → {arms, merge}`，`merge` 定义为链首 `cond_br` 块的**直接后支配块（IPD）**；不改 IR、不动 optimizer，选路处改读表 ⇒ 判定读结构而非读块号。底座与工作量实测见 §3.13（后支配变体 ≈60 行 + 一次 `rebuildCFG`）。
   - **2″ IR 扩字段**：`Terminator.cond_br` 增 `merge_block` ⇒ 语义最干净，但 **19 处构造点必须逐处填字段**（实测见 §7 成本列），回归面最大。
3. **收口站点补记**：给 `generateLabelDrivenBlockRange` 增加「帧停止块」返回值，外层据此复活/续发兄弟臂（等价于把 f124(修复13) 的 `return_generated` 复活机制推广到 `br`-回落形态）。

⇒ 4/7/9 **不落地**（硬要求未满足），转结构性长期项；R8/R8.1 全部插桩已还原（干净代次 `9490bf9f`/32663/`fdeebc14…`），还原后复跑六门与漂移见 §3.13。

### 3.13 候选 ① 谓词更正 + 还原后收尾复验（2026-10-05）

**对 §3.12 候选 ① 的自更正（必须，防按错误谓词落地）**：「then/else 两臂的臂尾均 `br` 到**同一**块 `m`」这一写法与本轮逐字读数不符，红三形实测为**两臂尾目标不同**：

| 形状 | then 臂尾 | else 臂尾 | 反向 merge |
|---|---|---|---|
| 形 4 | `ttag=br ttgt=6`（= `nmi` `for_cond_7`，**正向**）| `etag=br etgt=3`（`< nti=4`，**反向**）| 只有 else 臂 |
| 形 7 | `ttag=ret`（无回落边）| `etag=br etgt=5`（= `nmi`，正向）| 无 |
| 形 9 | 臂块 7/8 由 `S09H` 帧 `[4,9)` 平铺吞（`S09L i=7/8 term=br`）| 同左 | else 目标块 `ebi=2` 自身为 `.cond_br`（`ethen=7 eels=8`）|

⇒ 候选 ① 的可执行谓词必须改成「**本链 else 目标块为真实臂**（其终止符为 `br`/`ret` 而非 `cond_br` 链节点）**且其 `br` 目标 `<` 帧起点**（反向 merge ⇒ 帧内无收口站点）」，而**不是**「两臂尾同目标」；形 7 的 then 臂是 `ret` 终止 ⇒ 该形要求「一臂无回落边」也被允许。另需与 f067 的成因区分：f067 同站点 `etag=cond_br` ⇒ 其 else 块是**下一级链节点**，平铺帧走到它时由行内 `.cond_br` 处理器自带守卫帧发射（`S09L` 实测 `start=7 end=8`，臂未被吞）⇒ **「else 块 terminator 是否 `cond_br」是可二分字段，但只二分形 4 vs f067，对形 7/9 无覆盖**，故仍属选路层局部收紧，不能当本族总修法（该事实交由 §7 裁决时评估候选 ① 的真实覆盖面）。

**还原后收尾复验（干净树 = D 批代次 `9490bf9f`，md5 `fdeebc14daa456bb94437345ab771697`，32663 行，`grep -cF S09` = 0；clean `timeout 560 zig build` rc=0）**：

```text
c005_probe_run_tmp      PROBE_DONE total=17 same=17 differs=0
c005_rc4_probe_run_tmp  RC4_PROBE_DONE total=4 same=3 differs=1（差异项 = ref003_crash_attr_tmp rc=139，REF-003 已知项，非本族）
c005_rc5_probe_run_tmp  RC5_PROBE_DONE file=c005_rc5_merge_loss_tmp → IDENTICAL
c005_dowhile_probe_run  DOWHILE_PROBE_DONE total=2 same=2 differs=0
c006_tl_probe_run_tmp   C006_TL_GATE_DONE total=9 same=6 differs=3（红＝形 4/7/9，与 D 批基线逐字相同）
c006_d_probe_run_tmp    C006_D_GATE_DONE total=2 same=2 differs=0
```

⇒ **六门逐门等于 D 批落地时基线**（插桩零残留复证）。

**其余收尾实测（同一干净树）**：

```text
干净重建        timeout 560 zig build                                     rc=0
全量漂移门      DRIFT_DONE total=68 ok=68 diff=0 notemp=0 norow=0          （默认 --compile --no-debug-info 档，逐字节等值冻结基线）
单元/性能       zig build test --summary all → 21/21 steps、326/326 tests  rc=0
                ⚠ 日志含 `failed command: .zig-cache/o/55e2…/test --listen=-` 一行，但 Build Summary 全绿且步数/用例数与 D 批记录
                  （21/21 & 326/326）逐字相同 ⇒ 属被容忍子步的既有噪音，非本轮引入；已登记待查（不影响本门判定）。
```

**清理与结案**：R8/R8.1 的两枚扫描脚本（`r8_shadow_scan_tmp.sh`、`r81_narrow_scan_tmp.sh`）与 `/tmp` 侧读数产物（`r8_hits/`、`r81_hits/`、`r8_agg.sh`、`r81_paired.txt`、`probe_list.txt`、各 run 日志）已删除；任务 #67（R8-a 落地）/#68（R8-b 落地）以**否证**结案，#69 结案，新前置 = **#70 结构性路线裁决**。

**结构层现成底座实测（read-only，为 §7 裁决提供成本与可行性依据，干净树 `9490bf9f`）**：本族缺的「merge 归属」在编译原理上有**可证定义** = 链首 `cond_br` 块的**直接后支配块（IPD）**（LLVM 恢复 if/else merge 的标准做法），而仓库已有可复用底座：

| 已有 | 位置 | 复用性 |
|---|---|---|
| 支配树（Cooper–Harvey–Kennedy 迭代式，读 `block.predecessors` + 入口出发的 RPO） | `analysis.zig:94 computeDominators`、`:70 dominates`、`:88 strictlyDominates` | 把「前驱↔后继」「入口↔出口」对调即得后支配树 ⇒ **新代码仅一个反向遍历变体（≈60 行）**，无需重写算法 |
| CFG 前驱/后继重建 | `analysis.zig:270 rebuildCFG` | 后支配需要「出口根」：本 IR 的函数出口 = 终止符为 `.ret`/`.throw`/`unreachable` 的块集合，虚拟单根汇聚即可（实测 `Terminator` 共 6 tag，`ir.zig:568` 起 re-grep） |
| 现网调用者 | **仅 `optimizer.zig`**（`:617/:840/:843/:1171/:1234/:1235/:1249/:1810`）⇒ `native_linker.zig` **零调用**（`grep -rn 'rebuildCFG\|computeDominators' src/aot/*.zig` 实测） | ⇒ ② 的只读建表路线**必须**在发射入口前补一次 `rebuildCFG(func)`（O(块数)），并**懒构建**：仅在函数内出现 ≥1 个 `.cond_br` 且其两目标不在块序上单调时才建后支配树 ⇒ 避免给无链函数加常数开销（性能红线，§六「使编译器损失性能须先问」） |

⇒ 结论：**②「发射前只读建 `chain_id → {arms, merge}` 表」是唯一有可证定义支撑的路线**（其余路线的谓词均已被 R5/R6/R7/R8 四轮否证）；其真实工作量 = 后支配变体 ≈60 行 + linker 侧一次 `rebuildCFG` + 三处选路改读表，且**不改 IR、不动 optimizer 语义 ⇒ 无需重冻结基线**（仅需漂移门复证）。

### 3.14 R9 结构 merge（IPD）影子实测 + B 站点落地（2026-10-05；**形 4 转绿，本单门 `same=6` → `same=7`**）

**R9 插桩轮（流程规约 (a) 第五轮；代次 `19f2523a531736ca53e5af9e306bc91d`/32878 行；四枚站点 S10A/S10B/S10C/S10D + `R9_DUMP` 门控的 S10E 全表 dump；stderr-only、发射侧零行为改动、测后全删）**。插桩字节中性双证：九形门 `total=9 same=6 differs=3`（与 D 批基线逐字同判）+ 全量漂移 `68/68 diff=0`。

**四站点实测读数（105 脚本 = 68 语料 `pass/` + 37 永久探针）**：

| 站点 | 现口径 | IPD 一致率 | 分歧事件 | 语料命中面 |
|---|---|---|---|---|
| S10A/S10D（行内 `.cond_br` 主处理器，`merge_bi = blk_i`）；S10A 631 事件（`ipd=null` 170） | `merge = blk_i` | **374/375 逐字一致**；唯一非一致事件 `Container::make` node=6 `ipd=null`（非反向分歧，而是该节点无后支配汇合点） | 0 | — |
| S10B（线性摊平兜底，干净代次 `9490bf9f` `:10063`）50 事件 | `nested_merge_idx`（向后扫臂尾 `br`） | `ipd == nmi` ⇒ 恒等 19 事件；`ipd = null` 27 事件 | 4 事件，逐条被 P9b 的合取排除：`f032 CacheHandler::handle`（`ipd=6 nmi=null nti=5` 帧[0,9) ⇒ `ipd > nti` 且原口径为 null）、`f044 JsonTools::deepDiff`（`ipd=6 nmi=4 nti=23` 帧**[20,21)** ⇒ `ipd ∉ 帧`）、`f067 JsonDiff::diff`（`ipd=8 nmi=9 nti=6` 帧[0,26) ⇒ `ipd > nti`）、`f124 ContainerOrchestrator::autoscale`（`ipd=7 nmi=8 nti=6` 帧[0,11) ⇒ `ipd > nti`） | **0/68** |
| S10C（臂内循环派发前，N9 谓词） | — | — | 5 个通过脚本命中（f051/f056/f095/f102/f124） | **5/10 ⇒ 形 9 不落地**（本单第五次同位置否证） |

**九形探针的 B 站点分解（逐字读数，`/tmp/c006_tl_gate/*.build.log`）**：

```text
形 1/3/5/6/8（绿）  node=2 ipd=3 il=if_merge_2 nti=4 nmi=3  → eq_nmi ⇒ 恒等，不改写
形 4（红 → 本批转绿）node=2 ipd=3 il=if_merge_2 nti=4 nmi=6(for_cond_7) 帧[0,9) → 命中 P9b
形 7（红）          f=c006_tl_f7 node=2 ipd=null（then 臂 ret ⇒ 仅虚拟出口 V 后支配）⇒ IPD 路线结构性无覆盖
形 9（红）          不经过 B 站点（由 S09H 帧平铺吞臂，属 C 站点，面非 0）
```

**可落地判据 P9b（预登记后按读数落地；语料面 0 / 红形面 1）**：
`nmi 存在 ∧ nmi >= nti ∧ M = IPD(链节点) 存在 ∧ M ∈ [start_idx, end_idx) ∧ M < nti` ⇒ 把 merge 由 `nmi` 改判为 `M`，选路交下方既有 `nmi < nti` **乱序双臂模板**（与绿形 1/3/5/6/8 同源，非新机制）。

**落地实现（B 批代次 `0e38b018b24b9ba0aa358f8d26a7f012`/32796 行；vs 干净 D 批 `+134/−1`）**：

| 变更点 | 位置（B 批代次实测） | 内容 |
|---|---|---|
| helper `findChainMergeByPostDom` | `native_linker.zig:1080` | 117 行；反向 CFG（root=虚拟出口 `V=blocks.len`，children(V)=无后继块、children(b)=`predecessors`）显式栈后序 DFS → 反向 RPO → CK 定点；`m ∈ {NONE, V, node_idx}` ⇒ `null`。**只读、不改 IR、不动 optimizer ⇒ 无需重冻结基线**；显式栈规避 CODEGEN-004 递归深度风险 |
| B 站点选路 | `:10180`–`:10196`（`blk_p9` 在 `:10189`；**17 行替换 1 行**，净 +16） | 仅把 `if (nested_merge_idx) \|nmi\|` 的绑定改名 `nmi_raw` 并派生 `const nmi`；**两条分支体逐字未改** ⇒ 未命中判据时生成码逐字节不变 |
| 链节点求解 | 直接取 `ei` | `ei` = 本 else 块索引，即持有 `nested_cb` 的块（与影子轮指针扫描读数逐字一致）⇒ 零指针扫描、零额外遍历 |
| 懒计算守卫 | `nmi_raw >= nti` 前置 | 乱序形态（`nmi < nti`，绿形全部）与共享 merge 路径（`nmi == null`）**不进 IPD** ⇒ 无链函数与既有正确形态零常数开销 |
| 未改动 | 同形未测站点三处 `:9227` / `:9667` / `:10622`（D 批代次 `:9110`/`:9550`/`:10489`，均为 `if (nested_merge_idx) \|nmi\| {`）；`nmi == null` 的共享 merge 路径 | 影子轮只在 B 站点取数，改其余三处属无据扩散；`FIRE_NULLNMI` 语料面实测 0 ⇒ 无证据支持把 IPD 引入该路径 |

**门读数（B 批代次，两批串行门全绿，2026-10-05）**：

```text
c006_tl_probe_run_tmp     C006_TL_GATE_DONE total=9 same=7 differs=2（红＝形 7/9；形 4 转绿，无新红）
c006_d_probe_run_tmp      C006_D_GATE_DONE  total=2 same=2 differs=0
c005_probe_run_tmp        PROBE_DONE        total=17 same=17 differs=0
c005_rc4_probe_run_tmp    RC4_PROBE_DONE    total=4 same=3 differs=1（唯一红点仍 ref003_crash_attr_tmp rc=139，归 REF-003）
c005_rc5_probe_run_tmp    RC5_PROBE_DONE    IDENTICAL
c005_dowhile_probe_run    DOWHILE_PROBE_DONE total=2 same=2 differs=0
ref001_probe_run_tmp      PROBE_DONE        same=1 differs=3（逐字等于 2026-09-30 登记基线，差异全落属性引用侧）
全量漂移门                DRIFT_DONE total=68 ok=68 diff=0 notemp=0 norow=0   ← 硬零门（语料面 0 的复证）
官方 68 回归              TOTAL 68 / PASS 67 / SKIP 1 / FAIL_COMPILE 0 / FAIL_RUNTIME 0 / FAIL_DIFF 0
确定性巡检                SWEEP_DONE total=68 mismatch=0 notemp=0
基线抽查                  SPOT_DONE ok=5 bad=0
单元/性能                 zig build test --summary all → 21/21 steps、326/326 tests  rc=0
                          （仍含 `failed command: .zig-cache/o/55e2…/test --listen=-` 一行既有噪音，Build Summary 全绿，与 D 批记录逐字同判）
干净重建                  timeout 560 zig build                                     rc=0
插桩残留                  grep -cF 'S10' = 0、grep -c 'R9_DUMP' = 0、helper 定义 1 处 + 调用 1 处
```

**结构侧复证（非"输出恰好相等"）**：`ZIGPHP_AOT_KEEP_TEMP=1` 取形 4 的 `main.zig`，实测 `} else {` 分支内**先出现 `if (reg_7.toBool()) {` 守卫、守卫体内 `__for_0: while (true) { … break :__for_0; … }` 完整派发** ⇒ 臂受条件互斥保护且循环真实发射。

**编译开销实测（性能红线 §六「使编译器损失性能须先问」；同机单轮 `--compile --no-debug-info`，real 秒）**：

| 脚本（B 站点 IPD 调用数） | 落地后 | 干净 D 批基线 | 差值 |
|---|---|---|---|
| f044_json_deepops_merge_diff（1） | 10.52 | 10.61 | −0.09 |
| f067_json_parser_schema_path_diff（1） | 12.59 | 12.62 | −0.03 |
| f102_memory_gc_marksweep_refcount_gen（3） | 11.08 | 11.12 | −0.04 |
| f173_concurrency_primitives_sim（1） | 12.65 | 12.66 | −0.01 |

⇒ 全语料 IPD 实际调用 **24 次**（B 站点 50 事件中 `nmi >= nti` 者），最大帧 41 块；差值均在单次量测噪声内、且全量漂移门逐字节 `diff=0` ⇒ **非负向优化**（既不改生成码，也不产生可测编译期开销）。

**覆盖边界（本批只收形 4，禁止越界宣称）**：形 7 的链节点 `IPD = null`（then 臂以 `ret` 终止 ⇒ 只有虚拟出口后支配），属 §3.10 的「臂守卫坍缩」，IPD 路线**结构性无法覆盖**；形 9 需 C 站点判据，其语料面 5/10（非 0）⇒ 仍不落地。⇒ 本单门终态由 `same=9` 改为分阶段：A+D 批 `same=6` → **B 批 `same=7`**，余 2 形另立前置。

**遗留与后续（登记，未开工）**：①IPD 未做「每函数一次后支配树」缓存 ⇒ 同函数多链节点会重跑 CK（当前 24 次调用无成本压力；若命中面扩大则改为函数级缓存，成本一次 `buildCFG` + 一次定点）；②同形选路站点三处（`:9227` / `:9667` / `:10622`）结构同构但**未取数**，需各配一枚 B′ 影子探针再判是否同样改判；③`nmi == null` 共享 merge 路径不接 IPD（保守，实测面无证据）；④形 7 需换机制（臂守卫坍缩侧），形 9 需 C 站点可证判据。

**复测路径**：`bash fuzzy_scripts_720/tmp/c006_tl_probe_run_tmp.sh`（期望 `total=9 same=7 differs=2`）→ `bash fuzzy_scripts_720/tmp/c005_full_drift_tmp.sh`（期望 `diff=0`）。

**状态**：工作区已落地（未暂存、未提交，待「提交」指令）；R9 全部插桩（含 `R9_DUMP`/S10E dump）已随还原清除。

> **（2026-10-05 更正，巡检实测）** 本行是 **R9-B 落地当时**的读数：该批已于 2026-10-05 随「四批合一」提交为 **`497edc6`**（`git log -1` 实测），工作区对该文件仅剩 #74 纯注释批（`git diff --numstat` = `5 4`）。按 §4「历史值不改写」纪律保留原句，勿再据此判断为未提交。

### 3.15 R10 结构口径外扩影子轮（2026-10-05 结案：预登记四判据 + 九形/68 语料全量实测；结论 = a/c 无收益、b 第五次否证、d 触②号门槛）

**本轮唯一要答的四个问题（逐条对应 §7 遗留项，均为「既有 IPD 结构口径外扩是否有可证语料面」，不引入新机制）**：

| 编号 | 问题 | §7 项 |
|---|---|---|
| Q1 | R9-B 的 P9b 判据能否原样外扩到 **then 侧孪生选路站点**（当前唯一未取数的选路孪生）？ | c |
| Q2 | 链节点 IPD **恰为函数虚拟出口 V**（then 臂以 `ret` 终止 ⇒ 无 merge）能否作为独立判据改路到既有乱序双臂模板（形 7）？ | a |
| Q3 | `nested_merge_idx == null`（共享 merge）路径上，IPD 是否存在**非零可落地面**？ | d |
| Q4 | 形 9 的帧上界 `then_end` 由 `end_idx` 兜底 ⇒ 改用链节点 IPD **结构性收帧**是否有 0 语料面？ | b |

**插桩代次戳（规约 (b)，全部实测）**：干净树 = R9-B 代次 md5 `0e38b018b24b9ba0aa358f8d26a7f012`、32796 行；插桩代次 md5 `880ebfec90b84addc24f5877c0e6f53a`、32890 行；`diff` 实测 **`+96/−2`**，六处 hunk 逐字为 `1080c1080`（helper 签名增出参 `r10_raw`）、`1186a1187`（返回前写原值）、`8854a8856,8896`（S11C 41 行）、`9227a9270,9295`（S11A 26 行）、`10179a10248,10273`（S11B 26 行）、`10191c10285`（B 站点真实调用补 `null` 实参）。⇒ 净插入 94 行，**无一字进 `writer`**（全部 `std.debug.print` 直写 stderr），已落地判定逻辑逐字未改（B 站点仍用第二次独立调用取原值，代价 = 每事件两次 CK 定点，仅本轮存在）。还原备份 `/tmp/nl_backup_0e38b018_r10.zig`。

**三枚探针（tag → 站点以**干净代次**行号登记 → 读什么）**：

| tag | 站点（干净代次） | 现口径 | 打印字段 |
|---|---|---|---|
| `S11A` | `:9227` then 侧行内 `.cond_br` 的**结构选路站点**（`if (nmi >= nti)` 线性发射前） | `nmi` 直接由块序向后扫臂尾 `br` 得到 | 链节点 = 持有 `nested_cb` 的 then 块（`tryFindBlockIndex`）、`cls`（IPD 原值四分类）、`ipd`、`nti`、`nmi`、`ge`（`nmi>=nti`）、`hit`（P9b 同判据）、帧 `[s,e)`、`nlbl`（`nmi` 块标签） |
| `S11B` | `:10179` else 侧结构选路站点（**已落地 B 站点**，`:10180` 的 `nmi_raw` 之前） | 已落地 P9b（仅 `cls=M` 参与改路） | 同上，另 `ge=9` 专门标记 `nested_merge_idx == null` 的共享 merge 路径（Q3） |
| `S11C` | `:8854` then 臂帧上界 `then_end` 兜底计算完成处（**形 9 的坍缩路由**） | `else_bi >= blk_i` 取 `@min(ei,end_idx)`；`ebs > blk_i` 取 `@min(ebs,end_idx)`；否则 `end_idx` | `blk`（帧起点候选 `blk_i`）、`ebi`（本链 else 目标块 = 下一级链节点）、`etag`（其终止符类别：`br`/`cond_br`/`ret`/`other`/`none`/`null`）、`cls`/`ipd`、`rel`（0=无 IPD／1=落在 `(blk_i,end_idx)`／2=排在 `blk_i` 之前／3=其余）、`te`/`end`/`s`、`ebs` |

**IPD 原值四分类（本轮新增取数口径，防把「三种 null」混为一谈）**：`NONE` = 定点未收敛（无后支配点）；`V` = 后支配点为函数虚拟出口（全部路径离函数，**守卫子句/单臂直接返回**的签名，即 §3.14 形 7 的「IPD 路线结构性无覆盖」的真身）；`SELF` = 自指（异常，语料面应为 0）；`M` = 真实 merge 块。

**中性证据（两重均已实测）**：插桩代次 `timeout 560 zig build` rc=0；九形门读数 **`C006_TL_GATE_DONE total=9 same=7 differs=2`**，与 R9-B 干净代次登记值**逐字同判** ⇒ 第一重发射中性证据；第二重 = 全量 68 脚本漂移门 **`drift_ok=68 drift_diff=0`**（见本节末终态行）。

**九形逐字读数（`/tmp/c006_tl_gate/*.build.log`，实测）**：

```text
形 4（已转绿） [S11B] fn=__main__ node=2 cls=M ipd=3 nti=4 nmi=6 ge=1 hit=1 s=0 e=9 nlbl=for_cond_7   ← P9b 命中复证，判定未受插桩影响
形 7（红）     [S11B] fn=c006_tl_f7 node=2 cls=V ipd=99999 nti=3 nmi=5 ge=1 hit=0 s=0 e=8 nlbl=for_cond_7  ⇒ Q2 的结构性事实成立：真 merge = 函数出口
形 9（红）     [S11C] fn=__main__ blk=4 ebi=2 etag=cond_br cls=M ipd=3 te=9 end=9 s=0 rel=2 ebs=99999  ⇒ 帧 [4,9) 的真实 merge 排在帧起点之前（rel=2），臂 7/8 被吞
其余六形（绿）    S11B 逐字：shape1 / else_while / else_loop_tail 三者同为 `node=2 cls=M ipd=3 nti=4 nmi=3 ge=0 hit=1 s=0 e=9 nlbl=if_merge_2`；else_echo 同值但 `e=6`；two_elseif_loop 同值 `e=9`；**ifelse_loop（形 2）零触发**（不进该站点）。
                 ⇒ 五形读数完全一致且 `ipd == nmi`（几何恒等）、`ge=0`（本就走乱序双臂模板）⇒ 已落地判据对绿形**零改写**，与九形门 `same=7` 互证。
                 ⇒ **本轮判别性观察**：九形全部读数中 `cls ≠ M` 的**唯一事件 = 形 7 的 `cls=V`**（Q2 的取数面天然极窄，语料面须由全量轮给出）。
                 ⇒ **九份日志合计实测计数：S11A=0、S11B=7、S11C=1**。S11A 零触发 ⇒ Q1 的 then 侧孪生站点在本族探针上根本不进，其判定**只能**来自全量语料轮。
```

**候选判据（条件在读数出来前写死，禁止事后拟合；语料面 = 2026-10-05 全量轮实测终值）**：

| 编号 | 触发条件（全部为已打印字段） | 落地动作 | 语料面（**68 脚本全量实测**） | 硬要求 |
|---|---|---|---|---|
| R10-a（Q1） | `S11A ∧ ge=1 ∧ cls=M ∧ hit=1`（与 P9b 逐字同形） | 把 B 站点 `blk_p9` 选路块原样搬到 then 侧站点（DRY：同判据、同模板，不新增发射形态） | **0 事件**（站点本身有 10 事件，见下逐字读数） | 面必须 0 ⇒ **达成**，但**收益面亦为 0**（九形上 S11A 零触发）⇒ 判定改为「无收益不落地」 |
| R10-b（Q2） | `S11B ∧ ge=1 ∧ cls=V ∧ nlbl ∈ 窄四前缀循环头` | merge 不存在 ⇒ 改走 `:10309`（干净代次 `:10197` 之 `else` 分支）既有乱序双臂模板。**实测支撑**：本轮 grep 该模板全支，`nmi` 仅出现 1 次且在注释（`:10608`）⇒ 模板**不消费 merge 块**，无 merge 形态天然可发 | **5 事件 / 4 个通过脚本**（f007、f026、f067_min_repro、f102 ×2）；去掉 `nlbl` 收窄仍为同一 5 事件 ⇒ **否证（本族第五次）** | 面必须 0 ⇒ **未达成** |
| R10-c（Q3） | `S11B ∧ ge=9 ∧ hit=1`（共享 merge 路径） | 把 IPD 引入 `nmi == null` 路径 | **0 事件**（该路径本身 21 事件，全为 `hit=0`，分布见下） | 面必须 0 ⇒ **达成**，但同时**零可落地候选**（无任何 `ge=9 ∧ hit=1` 形状，红形亦不在此路径）⇒ 不落地 |
| R10-d（Q4） | `S11C ∧ etag=cond_br ∧ cls=M ∧ rel=2` | `then_end` 由 `end_idx` 改判为该链节点 IPD（真实 merge 在帧起点之前 ⇒ 帧不得吞其臂） | **0 事件**；但两枚合取**各自均非零面**：`cls=M ∧ rel=2` = 2 事件（f124 `__main__`，`etag=br`）、`etag=cond_br ∧ cls=M` = 4 事件（f067/f095/f124，全为 `rel=1`）⇒ 面为 0 纯靠两字段**交集**撑住 | **双重门槛**：① 语料面必须 0 ⇒ **达成**；② 必须给出与绿语料的**逐字二分证据** ⇒ **未达成**（见下「机制级结论」）。另：本判据含 `rel`（块序）属**帧上界层**，与 R5/R6/R7/R8/R8.1 五轮否证同层 ⇒ 仅"恰好面为 0"不足以落地 |
| 对照 | `cls=SELF`（异常自指） | — | **0 事件**；`cls=NONE` 亦 **0 事件** ⇒ IPD 四分类在 60 个选路站点事件上**穷尽**（32 `M` + 28 `V`），helper 无需第五分支 | 取证质量门，达成 |

**逐字读数（全量 68 语料，`/tmp/r10_hits/*.s11`，`sort -u` 去重）**：

```text
S11A 全 10 事件（then 侧孪生选路站点，Q1）：
  cls=M 的 9 事件全部满足 ipd == nmi（5/5、26/26、11/11、11/11、6/6、8/8、4/4、5/5、18/16*）
    ⇒ 块序口径在本站点**已给出结构 merge**，只是 `hit=0` 因 merge 排在 nti 之后（有序形态，本不需改路）
    （*node=39 为 ge=0 的乱序事件，ipd=18 ≠ nmi=16，两值皆 < nti=40 ⇒ 同走乱序双臂，无差）
  cls=V 的 1 事件 = JsonPath::query `node=8 ipd=99999 nti=11 nmi=10 ge=0 hit=0 s=7 e=8 nlbl=if_merge_12`
  ⇒ Q1 结论：**结构 merge 与块序 merge 在 then 侧从不给出不同答案** ⇒ 外扩既无风险面也无收益面。
S11B cls=V ∧ ge=1 ∧ hit=0 的 5 个绿事件（形 7 的逐字同签名复现，Q2 否证核心）：
  形 7（红）      c006_tl_f7                  node=2 cls=V ipd=99999 nti=3 nmi=5 ge=1 hit=0 s=0 e=8  nlbl=for_cond_7
  f026（绿）      LinkedList::pop             node=2 cls=V ipd=99999 nti=3 nmi=5 ge=1 hit=0 s=0 e=8  nlbl=while_cond_4
  f102（绿）      MarkSweepGC::mark           node=2 cls=V ipd=99999 nti=3 nmi=5 ge=1 hit=0 s=0 e=8  nlbl=foreach_cond_4
  f067_min_repro  MinJsonParser::parseValue   node=2 cls=V ipd=99999 nti=3 nmi=5 ge=1 hit=0 s=0 e=10 nlbl=while_cond_4
  f007（绿）      StringUtils::levenshtein2   node=2 cls=V ipd=99999 nti=3 nmi=5 ge=1 hit=0 s=0 e=14 nlbl=for_cond_5
  f102（绿）      RefCountGC::findCycle       node=2 cls=V ipd=99999 nti=5 nmi=7 ge=1 hit=0 s=0 e=10 nlbl=foreach_cond_6
  ⇒ 前三条与形 7 **除 `nlbl` 与函数名外逐字段全等（含帧 `[0,8)`）** ⇒ `cls=V ∧ ge=1` 在绿语料有 3 例全几何同形复现，Q2 判据彻底不可用。
S11C 全 10 事件（逐字，含 multiplicity）：
  br/M/rel=1  2 事件 = f051 `__main__ blk=3 ebi=2 ipd=6 te=6 end=18`、f177 `Graph::hasCycle blk=3 ebi=2 ipd=10 te=10 end=17`
              （两者 `te < end` ⇒ 帧上界**未走兜底**，本判据不作用于它们）
  br/M/rel=2  2 事件 = f124 `__main__ blk=28 ebi=23 ipd=21 te=31 end=31`、`blk=38 ebi=33 ipd=31 te=41 end=41`（`te==end` 兜底 + 反向 merge **真实存在于通过脚本**）
  cond_br/M/1 4 事件 = f067 `parseNumber blk=2 ipd=6 te=2 end=33`、f067 `parseNumber blk=26 ipd=29 te=26 end=33`（两臂帧 `te<end`）、
              f095 `optimize blk=13 ebi=12 ipd=17 te=21 end=21`、f124 `autoscale blk=4 ebi=2 ipd=7 te=11 end=11`（后两条 `te==end` ⇒ **与形 9 同走兜底、同 `etag=cond_br`，只差 `rel` 1 vs 2**）
  ret/V/rel=0 2 事件 = f056 `ORSet::remove blk=3 ebi=2 te=6 end=6`、f102 `RefCountGC::release blk=3 ebi=2 te=8 end=8`
  ⇒ 红侧唯一形 9 = `etag=cond_br ∧ cls=M ∧ rel=2 ∧ te==end`（该格语料 0 事件），但其两枚邻居格（`cond_br/M/1` 含兜底 2 事件、`br/M/2` 含兜底 2 事件）各非零
              ⇒ **`rel` 是唯一分隔线，而 `rel` 属块序层**（§3.12 已判定不可用）⇒ R10-d 触②号门槛。
```

**机制级结论（本轮唯一新增口径，供 R11 与 §7 裁决用）**：`etag`（本链 else 目标块的**终止符类别**）与 `rel`（其结构 merge 相对帧起点的**块序位置**）是两个**独立字段**，R10 实测显示：

1. `etag` 是**真结构不变量**（终止符类 = §3.10「臂守卫坍缩」本体的同一维度）：`cond_br` ⇒ else 目标是下一级链节点（臂未坍缩，链仍在递归），`br`/`ret` ⇒ else 目标是真实臂。**它在语料上不能单独二分**（`cond_br` 4 绿 + 红 1），但它是唯一与机制同维的字段。
2. `rel` 是行走器**停在哪**的静态投影，属 §3.12 已判定「行走运行时性质、不可作发射前区间判据」的那一层 ⇒ **R10-d 因含 `rel` 触②号门槛**。
3. ⇒ 形 7 的取数收获是把**选路站点彻底排除**（其七字段可被 4 个通过脚本逐字复现）；形 9 的取数收获是**把候选口径从「区间 + 计数」压到「终止符类别」单维**。二者共同的下一步 = §7 路线 **2′（链 `arms/merge` 归属表）在 `.cond_br` 处理器内按「else 目标是否链节点」分派**，而**不是**再找一条含块序的合取判据。

**R11 待定取证问题（不在本轮落地，登记）**：形 7 的丢失点在**被平铺帧吞掉的内层链级**（`S11B` 站点在帧入口，读不到内层），需一枚**只读内层链节点**的探针（在行内 `.cond_br` 处理器**递归进入臂内**时打印 `else 目标 terminator 类别 × 该臂帧界`），才能把「守卫子句可平铺」与「真三臂链不可平铺」在**同一站点**二分；该探针尚未存在 ⇒ R11 开轮前先审「是否已在 2′ 路线上直接改结构层」，避免第六次同层试错。

**全量语料影子（68 `pass/*.php`，逐脚本 KEEP_TEMP + 冻结基线逐字节比对 + 探针读数留存）**：扫描脚本 `/tmp/r10_scan.sh`，读数目录 `/tmp/r10_hits/*.s11`，聚合 `/tmp/r10_faces2.sh`（**必须用 v2**：v1 用 awk `eval()` 传判据，macOS 系统 awk（version 20200816）**无 `eval`**，每条记录报 `calling undefined function eval` 后因 `2>/dev/null` 静默 ⇒ 四候选面全报 0，而同一次运行的 `cls` 分布明写 24+24 事件自相矛盾 ⇒ 靠「零面必与总量交叉核对」这条既有规约才暴露；v2 改为「逐行压定长字段串 + `grep -E` 字面判据」）。终态行实测：

```text
S11_SHADOW_DONE total=68 hit_scripts=38 compile_fail=0 drift_ok=68 drift_diff=0 drift_notemp=0 drift_norow=0
```

⇒ **第二重中性证据达成**：插桩代次对 68 个冻结基线脚本**逐字节零漂移**，与九形门 `same=7` 互证 ⇒ 净插入 94 行确无一字进 `writer`。

**还原后收尾（干净树 = R9-B 代次 `0e38b018…`/32796 行，`grep -c '[S11'` = 0；clean `timeout 560 zig build` rc=0 / 64s）**：见本节末「门复跑」表（§3.15.1）。

**状态**：R10 插桩已全删（工作区回到 R9-B 代次，未暂存、未提交）；四问结论 = **a/c 无收益不落地、b 否证、d 触②号门槛不落地** ⇒ 形 7/9 继续转结构性长期项（§7 路线 2′）。

#### 3.15.1 还原后门复跑（2026-10-05，干净树 `0e38b018…`/32796 行，`grep -c '[S11'` = 0）

**clean 重建**：`timeout 560 zig build` → **rc=0 / 64s**（`real 1:03.53`，user 61.89s）。

**七道探针门（串行，禁并发编译）实测**：

```text
C006_TL_GATE_DONE total=9 same=7 differs=2          ← 等于 R9-B 落地时登记值（红 = 形 7/9）
C006_D_GATE_DONE  total=2 same=2 differs=0
PROBE_DONE        total=17 same=17 differs=0         （c005 十七形等值门）
RC4_PROBE_DONE    total=4 same=3 differs=1           （差异项 = ref003_crash_attr_tmp rc=139，REF-003 已知项，非本族）
RC5_PROBE_DONE    file=c005_rc5_merge_loss_tmp → IDENTICAL（含 rc5fi_only / rc5fj_only 两形）
DOWHILE_PROBE_DONE total=2 same=2 differs=0
PROBE_DONE        same=1 differs=3                   （ref001 门，等于 2026-09-30 登记基线）
```

⇒ **七门逐门等于 R9-B 落地基线** ⇒ 插桩零残留复证（第一阶段）。

**第二阶段（全量 / 官方 / 巡检 / 抽查 / 单元，串行复跑，均等于 R9-B 落地记录）**：

```text
DRIFT_DONE   total=68 ok=68 diff=0 notemp=0 norow=0      （硬零门达成，默认 --compile --no-debug-info 档）
官方 harness TOTAL 68 / PASS 67 / FAIL_COMPILE 0 / FAIL_RUNTIME 0 / FAIL_DIFF 0 / SKIP 1（SKIP 仍为 f004）
SWEEP_DONE   total=68 mismatch=0 notemp=0                 （编译期确定性巡检）
SPOT_DONE    ok=5 bad=0                                   （冻结基线抽查）
Build Summary: 21/21 steps succeeded; 326/326 tests passed（rc=0）
```

⇒ **十项复验全绿**（七探针门 + 漂移 + 官方 + 巡检 + 抽查 + 单元），R10 插桩零残留复证完成。

**R10 结案口径（四问答案，写进 §7 裁决行）**：

| 问 | 答案（全为实测） | 是否产生可落地判据 |
|---|---|---|
| Q1（§7 c） | then 侧孪生站点 10 事件，`cls=M` 的 9 条**全部 `ipd == nmi`** ⇒ 结构口径与块序口径在此站点**从不给出不同答案**；`ge=1 ∧ hit=1` 面 = 0 且红形零触发 | **否** ⇒ 外扩无收益，站点保持现口径（§7 c 闭环） |
| Q2（§7 a / 形 7） | `cls=V ∧ ge=1` 语料面 = **5 事件 / 4 通过脚本**，其中 3 条与形 7 **逐字段全等（含帧 `[0,8)`）仅 `nlbl` 不同** | **否（第五次否证）** ⇒ 形 7 的阻塞物**不在选路站点**，改登记为「内层链级取证」（R11 问题） |
| Q3（§7 d） | `nmi == null` 路径 21 事件，`hit` 全 0 ⇒ 该路径**无任何结构 merge 落在帧内且早于 `nti`** 的形态 | **否** ⇒ 该路径不接 IPD（§7 d 闭环，且为「无证据即不改」补上实测依据） |
| Q4（§7 b / 形 9） | 精确格 `etag=cond_br ∧ cls=M ∧ rel=2` 面 = 0，但两枚邻居格各非零（`cond_br/M/1` 含 `te==end` 兜底 2 事件 = f095/f124；`br/M/2` 含兜底 2 事件 = f124） ⇒ 唯一分隔线是 `rel`（块序） | **否** ⇒ 触本判据自设的②号门槛（同层五轮否证）⇒ 形 9 仍走结构层（§7 路线 2′） |
| 附带收获 | IPD 四分类在 60 个选路事件上**穷尽**（`M` 32 / `V` 28，`NONE`/`SELF` 均 0）；`etag`（else 目标块的终止符类别）是本轮唯一与 §3.10「臂守卫坍缩」同维的结构字段 | 供 R11/2′ 使用 |

⇒ **R10 不产生落地批次**；形 7/9 的下一步 = §7 路线 **2′（链 `arms/merge` 结构层）**，且必须先做「表派生帧界 vs 现口径帧界」的全语料一致性影子轮（规约 (a)），禁止再找含块序的合取判据。

### 3.16 R11 链结构表（arms/merge）一致性影子轮（2026-10-05 结案；**本单第六次否证，且落在 §3.15 判定为「最后候选」的结构层**）

**本轮只答一个问题**（§3.15 末行 + §7 R10 行的强制前置）：**把发射帧上界从「现口径（块序 + 兜底 `end_idx`）」换成「链结构表派生（CFG 可达性 ⊖ 结构 merge ⊖ 兄弟臂）」，在 68 个通过脚本上是否逐字节中性？** 不引入新机制、不碰 IR、不建持久表 —— 只做「同一函数内两种帧界口径的一致性对拍」。

**插桩代次戳（规约 (b)，全部实测）**：干净树 = R9-B 代次 md5 `0e38b018b24b9ba0aa358f8d26a7f012`、32796 行；插桩代次 md5 `779bda272412a75c3bf26ecb7b4fbdcb`、33060 行；`diff` 实测 **`+264/−0`**（纯插入、零删除），三枚只读探针函数（`probeR11ReachSeen`、`probeR11FrameTable`、`probeR11Handback`，均插在 `findChainMergeByPostDom` 之后）+ 四枚调用点。全部输出走 `std.debug.print` 直写 stderr，**无一字进 `writer`**；还原备份 `/tmp/nl_backup_0e38b018_r11.zig`。

**表口径定义（纯 CFG，判据只用终止符类别 + 可达性 + IPD，块序仅用于把集合写成区间）**：

| 字段 | 定义 |
|---|---|
| `owner` | 反查链首：满足 `blocks[b].terminator == .cond_br ∧ idx(else_block) == else_hint` 的块 |
| `arms` / `narm` | 自 `owner` 沿「else 目标本身亦为 `.cond_br`」递归取链节点，收集每级 `then` 块 + 末级 `else` 块（守卫 16 级）|
| `ft` | 末级 else 块的终止符类别（`br`/`ret`/`throw`/`notcond`/`null`）|
| `m` | `findChainMergeByPostDom(owner)` = 链首的 IPD（`99999` = 仅虚拟出口 V ⇒ 无 merge，即 §3.15 的 `cls=V` 形态）|
| `teA` | 首个**不满足**「自 `frame_start` 前向可达（截止 `m`）」的块号（`≥ frame_start`）⇒ **只截止结构 merge** |
| `teB` | 同上，再额外截止 `arms` 中排在 `teA` 之后的兄弟臂入口 ⇒ **merge + 臂集合** |
| `ovrA` | `teA < te_cur` ⇒ 现口径**多走**了表判定不可达的块（表口径会收帧）|
| `cutA` | `teA > te_cur` ⇒ 现口径**截断**了表判定可达的块（表口径会放帧）|
| `swuA` | `[teA, te_cur)` 内**全部**不可达 ⇒ 「收帧无损」候选 |
| `sw` | `te_cur -\| teA`（现口径比表口径多走的块数）|

**四枚站点**（全部不触碰任何发射值）：`S12T1`（形 9 路由 = `then_end` 兜底 `blk:` 式完成处，插桩代次 `:9116`）、`S12T2`（then 块即循环头的臂帧，`:8928`）、`S12T3`（B 站点线性分支 `cs18_end`，`:10477`）、`S12H1`（**五条件 merge 回传判据之前**，读 `last_loop_fallthrough_idx` 及五条件逐项真值，`:9127`）。

**中性双证（两重均实测，缺一即还原）**：① 插桩代次 `timeout 560 zig build` rc=0，九形门 **`C006_TL_GATE_DONE total=9 same=7 differs=2`** 与 R9-B 干净代次登记值**逐字同判**；② 全 68 语料 KEEP_TEMP + 冻结基线逐字节比对 **`S12_SHADOW_DONE total=68 hit_scripts=25 compile_fail=0 drift_ok=68 drift_diff=0 drift_notemp=0 norow=0`** ⇒ 净插入 264 行确零发射副作用。

**事件总量与聚合（45 行读数 = 35 `S12T*` + 10 `S12H1`；聚合 `/tmp/r11_faces.sh` 的 faces 行已与 raw `grep -c` 逐字段交叉核对：`ovrA=1` 12 ✓、`join=1` 5 ✓、`join=0` 2 ✓）**：

```text
events=35  ovr1=12  ovr1_swu1=7  join1=5  join0=2  join_na=28
分解（35 = 12 + 6 + 17；ovrA 与 cutA 实测互斥，同现事件 0）：
  ovrA=1（表口径收帧） 12 事件 / 11 个通过脚本：f007 f025 f026 f043 f067 f067_min_repro f072 f080 f095 f102 f124
      ├─ ∧ swuA=1（收帧无损）7 事件 / 6 脚本：f007 f026 f067_min_repro f095 f102×2 f124
      └─ ∧ swuA=0（收帧有损 ⇒ 踢出可达块）5 事件：f025 f043 f067::JsonDiff::diff f072 f080
  cutA=1（表口径放帧） 6 事件 / 5 个通过脚本：f010 f044 f067::parseNumber×2 f102::markGen f171
      （全部 sw=0，即现帧在此处为**故意的空帧** `te == fs`，臂体已由链上层在帧外落好 ⇒ 放大帧界会重发）
  表界 == 现界        17 事件（ovrA=0 ∧ cutA=0）
站点分布：S12T1=10（其配对 S12H1 亦 =10，逐事件一一对应）S12T2=1（f105 insertNonFull，ovrA=0）S12T3=24
命中面并集：ovrA=1 ∪ cutA=1 = **18 事件 / 15 个通过脚本**（25 个命中脚本中的 15 个）
```

**否证 R11-e（`then_end := 表派生帧界` 直译落地）**：语料面 = **18 事件 / 15 个通过脚本 ≠ 0** ⇒ 违反规约 (a) 的「命中面必须 0」硬要求 ⇒ **不落地**。且**双向都变**：12 例表口径更短（其中 5 例会把**可达**块踢出发射 = 有损），6 例更长（现口径在此处故意发空帧）。

**否证 R11-f（最窄候选：仅当「多走的那一段全部不可达」才收帧，`ovrA=1 ∧ swuA=1`）**：语料面 = **7 事件 / 6 个通过脚本 ≠ 0** ⇒ 连「无损收帧」都会改生成码 ⇒ **不落地**。机制解释（本轮唯一新增口径）：**发射帧 `[start, then_end)` 从设计上就不是 `start` 的 CFG 可达域**，而是覆盖多个链层的块号区间 —— 兄弟臂块对本臂不可达、却必须由本帧落盘（`swuA=1` 的 6 个绿脚本正是此形态）⇒ 用可达性裁剪它等价于删掉链上层赖以续发的臂块。

**否证 R11-g（兄弟臂集合对帧界的增益 = §7 路线 2′ 的 `arms` 半边）**：`teA != teB` 的事件数 = **0 / 35** ⇒ 在九形 + 68 语料全部读数上，「额外截止兄弟臂入口」**从不**改变帧界一个字节（merge 截止已给出同一上界）⇒ **链结构表的 `arms` 列对帧界零信息增益**，路线 2′ 的「表」形态被实测削掉一半。

**红绿同格逐字复现（本轮最硬的一条否证证据）**：

```text
形 9（红，S12T1）  __main__            fs=4  te=9  end=9  owner=0  m=3  teA=7  narm=3 arms=1,7,8    ft=br armb=3 ovrA=1 cutA=0 swuA=1 sw=2 tal=if_then_8
f124（绿，S12T1）  autoscale           fs=4  te=11 end=11 owner=0  m=3  teA=6  narm=3 arms=1,6,7    ft=br armb=3 ovrA=1 cutA=0 swuA=1 sw=5 tal=if_then_10
f095（绿，S12T1）  optimize            fs=13 te=21 end=21 owner=10 m=12 teA=16 narm=3 arms=11,16,17 ft=br armb=3 ovrA=1 cutA=0 swuA=1 sw=5 tal=if_then_21
⇒ 三条读数**每个结构字段同格**（`narm=3`、`ft=br`、`armb=3`、`m` 存在且 `m<fs`、`teA==teB`、`ovrA=1`、`cutA=0`、`swuA=1`、`tal` = 末臂块），只差块号 ⇒ 表口径无二分能力。

形 7（红，S12T3）  c006_tl_f7          fs=3 te=8 end=8 owner=0 m=99999 teA=4 narm=3 arms=1,3,4 ft=br armb=2 ovrA=1 swuA=1 sw=4
f026（绿，S12T3）  LinkedList::pop     fs=3 te=8 end=8 owner=0 m=99999 teA=4 narm=3 arms=1,3,4 ft=br armb=2 ovrA=1 swuA=1 sw=4   ← **除函数名外逐字节全等**
f102（绿，S12T3）  MarkSweepGC::mark   fs=3 te=8 end=8 owner=0 m=99999 teA=4 narm=3 arms=1,3,4 ft=br armb=2 ovrA=1 swuA=1 sw=4   ← 同上
⇒ 形 7 的**整条静态签名**被 2 个通过脚本逐字复现 ⇒ **任何发射前静态判据都不能修形 7**（第六次否证，且落在 §3.15 判定的「最后候选层」）。
```

**正向读数（本轮唯一可落地线索，全部实测）**：`S12H1` 在 T1 路由站点取到 10 事件（与 `S12T1` 一一对应），三条关键事实：

```text
1) lfi 存在的事件 = 7，且 **7/7 全部 lfi == m**（链的 IPD）：
     f051 __main__ m=2 lfi=2 ／ f056 ORSet::remove m=2 lfi=2 ／ f095 optimize m=12 lfi=12
     f102 RefCountGC::release m=2 lfi=2 ／ f124 autoscale m=3 lfi=3
     f124 __main__#1 m=23 lfi=23 ／ f124 __main__#2 m=33 lfi=33
   ⇒ `last_loop_fallthrough_idx`（动态）与 `findChainMergeByPostDom`（静态）是**同一块的两种求法**，
     静态侧从不给出新信息 ⇒ 既解释路线 2′ 的表为何零增益，也解释判别性为何只能落在回传侧。
2) 五条件回传实测触发 = `join=1` 5 事件 / 5 脚本；`join=0` 2 事件（f124 `__main__` ×2，`isLH=1` ⇒ 正确拒绝，
   且二者 `ovrA=0` ⇒ 无帧吞并，拒绝无副作用）；`lfi==null` 3 事件（f067 `parseNumber` ×2、f177 `hasCycle`，三者 `ovrA` 均 0）。
3) ⇒ **合取 `ovrA=1 ∧ lfi==null`（帧在吞不可达块、且无 merge 回落可回传）在 T1 站点语料面 = 0，唯一命中 = 形 9**
   （T1 的 `ovrA=1` 只有 f095/f124 两条且 `lfi` 均有效；`lfi==null` 的三条 `ovrA` 均 0）。
```

**判据缺口（诚实登记，不得据此落地）**：`S12H1` 只装在 T1 路由 ⇒ **T3 站点（形 7 + 24 事件，含 10 条绿 `ovrA=1`）无回传读数**，故「`ovrA=1 ∧ lfi==null`」的 0 面结论**只覆盖 T1 路由（形 9）**，不得外推到形 7；而形 7 已被上面的逐字同格复现彻底排除在静态判据之外。

**路线 ③ 干净树锚点（2026-10-05 re-grep 实测，代次 `0e38b018`/32796 行；不再做插桩↔干净行号换算，只记 grep 结果）**：五条件 merge 回传在**整文件只有一处** —— `grep -n lfi_is_join` = **`8871`**（条件式）/ **`8877`**（`if (lfi_is_join)`），其消费入口 `if (self.last_loop_fallthrough_idx) |lfi|` = **`8865`**，即 R11 装 `S12H1` 的 T1 路由站点。T3 侧的 `cs18_end` 线性分支为 **`10202`**（求解）/ **`10214`**（`generateLabelDrivenBlockRange(nti, cs18_end, …)` 调用），该调用之后**没有任何 `last_loop_fallthrough_idx` 读取**（`grep -n` 在 `10214` 之后的下一处读点是 `11894`，属另一函数族站点）⇒ 路线 ③ 在 T1 侧是「把动态回落换成静态回落（`lfi==null ∧ m` 存在 ⇒ 以 `m` 为目标）」的**改判**，在 T3 侧则是**新增回传消费者**，两者代价与回归面不同，须分开裁决。

**机制级结论（写进 §7 裁决行）**：红形缺的不是「链的 `arms/merge` 归属表」（实测零增益），而是**帧收口信号本身** —— 绿脚本靠「循环出口回落到链的 IPD 块」触发既有五条件回传，把 merge 交还链上层，上层因此能续发被本帧吞掉的兄弟臂；形 9 该回落信号缺失（`lfi==null`）⇒ 无回传 ⇒ 兄弟臂被吞标。**唯一与该机制同形的落地路线 = §7 路线 ③（帧收口站点回传）**：`lfi==null` 且链 IPD 存在时以 `m` 为回传目标（把动态回落换成静态回落），而非再建静态表或改区间判据。

**状态**：R11 插桩已全删（工作区回到 R9-B 代次 `0e38b018…`/32796 行，`grep -c 'S12'` = 0、`grep -c 'probeR11'` = 0，vs HEAD `+385/−30` 复现）；**不产生落地批次**；六轮同层否证闭合（区间/上界 R5 → 臂归属 R6 → 臂重联 R7 → terminator 盲区 + 计数 R8/R8.1 → 选路站点静态字段 R10 → **结构帧界 R11**）⇒ 形 7/9 的落地前置**只剩** §7 路线 ③，需老铁点头后才动编译器源码。

#### 3.16.1 还原后收尾复验（2026-10-05，干净树 `0e38b018…`/32796 行）

**clean 重建**：`timeout 560 zig build` → **rc=0 / 63.65s**（user 61.72s）。

**门复跑（串行，禁并发编译；2026-10-05 实测，十二道腿全等于 R9-B 落地记录）**：

```text
G1  c006 九形门        C006_TL_GATE_DONE total=9 same=7 differs=2      ← 红点仍 = 形 7/9
G2  c006 D 旁门        C006_D_GATE_DONE  total=2 same=2 differs=0
G3  c005 十七形        PROBE_DONE        total=17 same=17 differs=0
G4  c005 RC-4 诊断门   RC4_PROBE_DONE    total=4 same=3 differs=1      ← 唯一红点 = ref003_crash_attr_tmp（REF-003，非本族）
G5  c005 RC-5 合串     IDENTICAL|c005_rc5_merge_loss_tmp|rc=0
G6  c005 do-while      DOWHILE_PROBE_DONE total=2 same=2 differs=0
G7  ref001             PROBE_DONE        same=1 differs=3              （逐字等于 2026-09-30 登记基线）
G8  冻结基线漂移（硬零门）DRIFT_DONE total=68 ok=68 diff=0 notemp=0 norow=0   ⇒ 基线**不需重冻结**
G9  官方 harness       TOTAL 68 / PASS 67 / FAIL_COMPILE 0 / FAIL_RUNTIME 0 / FAIL_DIFF 0 / SKIP 1（SKIP 仍为 f004）
G10 编译期确定性巡检    SWEEP_DONE        total=68 mismatch=0 notemp=0
G11 冻结基线抽查       SPOT_DONE         ok=5 bad=0
G12 zig build test     Build Summary: 21/21 steps succeeded; 326/326 tests passed，RC=0
```

**G12 复测说明（诚实登记）**：门串脚本里 G12 写的是 `zig build test 2>&1 \| tail -3` ⇒ 只留下 `✅ All performance tests passed` 与既有的 `failed command: ./.zig-cache/o/55e2…/test … --listen=-` 幻影行（`ci_integration.test.CIRunner` 再调用自身二进制泄漏的 stderr，开批前基线日志同位置逐字一致），**未取到 summary 与 rc**。门串释放编译窗口后单独复跑 `timeout 560 zig build test --summary all` ⇒ **`RC=0`**、`Build Summary: 21/21 steps succeeded; 326/326 tests passed`。

⇒ **十二道门逐门等于 R9-B 落地基线** ⇒ R11 的 264 行插桩零残留复证完成（代次 `0e38b018…`/32796 行、`grep -c 'S12'`=0、`grep -c 'probeR11'`=0、`git diff HEAD --numstat` = `385 30`）。

### 3.17 R12 静态回落目标（链 IPD）可行性探针轮（2026-10-05 开跑；补 §3.16 自登记的那一条缺口）

**本轮只答一个问题**（§3.16「判据缺口」+ §7 R11 行的强制前置）：**路线 ③ 的回传目标能否由「发射前静态可算的链 IPD」给出 —— 以及它在 T1（形 9）与 T3（形 7）两个路由站点各自的语料命中面是多少。** R11 只在 T1 装了动态回传读数（`S12H1`），T3 侧 24 事件无读数，且 R11 的 `m` 列一律是 `IPD(owner)`（链首反查），**没有**测过 R9-B 落地代码实际调用的 `IPD(ei)`；本轮把两侧、两个候选节点全部测齐。不引入新机制、不碰 IR、不改任何发射值 —— 只做「静态候选 vs 动态回落」的同站点一致性对拍。

**插桩代次戳（规约 (b)，全部实测）**：干净树 = R9-B 代次 md5 `0e38b018b24b9ba0aa358f8d26a7f012`、32796 行；插桩代次 md5 **`91f2d09ef4f58990e6a627b7b8d073ee`**、**32901 行**；vs 干净备份 `diff` 实测 **`+105/−0`**（`grep -c '^<'` = **0**，纯插入），vs HEAD `git diff HEAD --numstat` = **`490 30`**（= 落地批 `385 30` + 净插入 105，删除行数不变 ⇒ 两路独立复证「只加不改」）。备份 `/tmp/nl_backup_0e38b018_r12.zig`。

**探针与站点（一枚只读函数 + 八处调用，全部不触碰任何发射值）**：

| 站点 | 插桩代次行号 | 取的数 |
|---|---|---|
| `probeR12Node`（唯一探针函数，插在 `findChainMergeByPostDom` 之后） | `:1195` | 见下表字段 |
| `T1-JOIN`（`lfi` 捕获块首 = 既有五条件回传的入口） | `:8958`（nk=F）/ `:8960`（nk=E） | 动态 `lfi` 与两个静态候选**并排**，直接测「静态 IPD == 动态回落」是否恒等 |
| `T1-NULL`（给该 `if` **新加的 `else` 支**，仅打印） | `:8992`（nk=F）/ `:8994`（nk=E） | 形 9 路径：无回落记录时静态候选能否凑齐五条件 |
| `T3-PRE`（`cs18_end` 求解后、派发前） | `:10315` / `:10316` | 帧进入时的 ambient `lfi` |
| `T3-POST`（派发返回后 —— 现口径此处**没有任何 `lfi` 消费者**） | `:10318` / `:10319` | 本帧跑完后的 `lfi` 现值（现被整体丢弃的那条信息）+ 静态候选 |

字段口径（`nk=F` 候选节点 = 帧起点 `fs`；`nk=E` = 本 `cond_br` 的 else 目标 `ei`；NONE = `18446744073709551615`）：`m` = `findChainMergeByPostDom(node)`；`pos` = `m < fs ∨ m == ei`（T1 五条件之「位置」）；`np` = `countPredecessors(m)`；`isLH`/`iscb`/`iseb` = 循环头 / 本循环 cond / 本循环 exit；`pro` = `processed.contains(m)`；`nsrc`+`src0` = 帧 `[fs, te)` 内以 `.br` 落入 `m` 的源块数与首源块（决定 PHI 能否按边物化）；`nphi` = `m` 块 PHI 条数；`tt` = `m` 块终止符类别（`b`/`c`/`r`/`t`/`s`/`u`）；`nbl` = 函数块数；`ldf` = `defer_loop_fallthrough`。**全部输出走 `std.debug.print` 直写 stderr，无一字进 `writer`；不写 `processed`、不写任何 `self` 字段、不改控制流。**

**中性证据第一腿（实测）**：`timeout 560 zig build` → **rc=0 / 63.78s**。九形门 **`C006_TL_GATE_DONE total=9 same=7 differs=2`**，红点逐字仍是 `c006_tl_fncontext_loop_tmp`（形 7）与 `c006_tl_ifarm_loop_tmp`（形 9）；D 旁门 **`C006_D_GATE_DONE total=2 same=2 differs=0`** ⇒ 与 R9-B 登记读数同判。

**九形侧读数（`/tmp/c006_tl_gate/*.build.log`，本轮实测原文；其余 7 形 0 行 ⇒ 与 R11 站点覆盖一致）**：

```text
形 9（红，T1-NULL）__main__  nbl=9
  nk=F node=4 m=6  fs=4 te=9 end=9 ei=2 lfi=NONE pos=0 np=1 isLH=0 iscb=0 iseb=0 pro=1 nsrc=0 nphi=0 tt=b
  nk=E node=2 m=3  fs=4 te=9 end=9 ei=2 lfi=NONE pos=1 np=3 isLH=0 iscb=0 iseb=0 pro=0 nsrc=0 nphi=0 tt=r
形 7（红，T3）    c006_tl_f7  nbl=8   （T3-PRE / T3-POST × nk=F / nk=E 四行同值）
  nk=F node=3 m=NONE fs=3 te=8 end=8 ei=2 lfi=NONE pos=0 np=0 isLH=0 iscb=0 iseb=0 pro=0 nsrc=0 nphi=0 tt=n
  nk=E node=2 m=NONE fs=3 te=8 end=8 ei=2 lfi=NONE pos=0 np=0 isLH=0 iscb=0 iseb=0 pro=0 nsrc=0 nphi=0 tt=n
```

**两条决定性结论（先于语料面成立，全部实测）**：

1. **形 9 可被路线 ③ 命中，且命中面用的就是 T1 既有五条件**：静态候选 `IPD(ei)=3` 使 `pos=1 ∧ np=3>1 ∧ isLH=0 ∧ iscb=0 ∧ iseb=0 ∧ pro=0` **六项全真**（与 `lfi_is_join` 的判据逐条同形；干净树 `:8871`／插桩代次 `:8963`），而帧起点候选 `IPD(4)=6` 被 `np=1`（单前驱）与 `pro=1`（已处理）双否 ⇒ **候选节点必须是 `ei`，不是帧起点**。`nphi=0 ∧ nsrc=0` ⇒ 该 merge 块无 PHI、帧内无 `.br` 落入边 ⇒ 静态路径**不需要**（也没有）`lsrc` 的 PHI 物化 analog；`tt=r` ⇒ `m=3` 是函数级共享 `ret` 块（与 §4「共因」行的 `f124(修复13)` 形态同源），回传后由外层在正确缩进发 `ret` 并复活兄弟臂。
2. **形 7 不属于路线 ③ 的适用范围**：`IPD(nti)=null` 且 `IPD(ei)=null`（`nbl=8`、`tt=n`）⇒ 该链**不存在结构 merge**（全部路径只汇入虚拟出口 V，即 §3.15 `cls=V` 形态），路线 ③ 的前置「`m` 存在」在形 7 上**不可满足**；`T3-POST` 的 `lfi` 亦为 `NONE` ⇒ 帧内派发**既没产生动态回落、也没有静态回落目标**，T3 新增消费者拿不到任何可回传的对象 ⇒ 形 7 与 006 族其余各形一样被排除，但排除理由**不同于**前六轮（不是「判据二分不开红绿」，而是「机制的前置条件在红形上不成立」）。

#### 3.17.1 全量语料面读数（2026-10-05 实测，路线 ③ 定面完成）

**中性证据第二腿（实测）**：68 语料逐脚本实时编译（默认 `--compile --no-debug-info` 档 + `KEEP_TEMP`）与冻结基线比 md5+行数 ⇒

```text
S13_SHADOW_DONE total=68 hit_scripts=24 compile_fail=0 drift_ok=68 drift_diff=0 drift_notemp=0 norow=0
```

⇒ **插桩代次对全 68 语料逐字节中性（硬零门满足）**，且 24 个语料脚本在 T1/T3 两站点有读数（非零覆盖面，读数可用于定面）。聚合源：`/tmp/r12_all.txt` **122 行 / 26 个来源**（语料 24 + 九形侧 2）。

**事件分布（读数量 | 五条件真 | 五条件∧未 processed；PASS=语料脚本，SHAPE=九形/D 旁门）**：

| 站点/候选节点 | PASS 读数 | PASS 五真 | PASS 五真∧¬pro | SHAPE 读数 | SHAPE 五真 | SHAPE 五真∧¬pro |
|---|---|---|---|---|---|---|
| `T1-JOIN` nk=F（候选=帧起点 `fs`） | 7 | 1 | 0 | 0 | 0 | 0 |
| `T1-JOIN` nk=E（候选=`ei`） | 7 | 0 | 0 | 0 | 0 | 0 |
| **`T1-NULL` nk=F** | 3 | **0** | 0 | 1 | 0 | 0 |
| **`T1-NULL` nk=E** | 3 | **0** | 0 | 1 | **1** | **1** |
| `T3-PRE` nk=F / nk=E | 24 / 24 | 0 / 0 | 0 / 0 | 1 / 1 | 0 / 0 | 0 / 0 |
| `T3-POST` nk=F / nk=E | 24 / 24 | 0 / 0 | 0 / 0 | 1 / 1 | 0 / 0 | 0 / 0 |

⇒ **路线 ③ 判据（`lfi==null` ∧ 静态候选满足 T1 既有五条件）的语料命中面 = 0 事件 / 0 脚本**；红形命中面 = 1 事件（形 9 的 `nk=E` 行，五条件+`¬pro` 全真）；7 个绿形在该站点 **0 读数**（与 R11 站点覆盖一致，不产生红绿混淆）。这是七轮里第一次「判据成立且语料面为 0」。

**语料侧 6 条 `T1-NULL` 读数原文（说明为何全被排除）**：

```text
f067_json_parser_schema_path_diff  JsonParser::parseNumber  nbl=33
  nk=F node=2  m=6  fs=2  te=2  end=33 ei=2  pos=0 np=2 isLH=0 iscb=0 iseb=0 pro=0 nsrc=0 nphi=1 tt=c
  nk=E node=2  m=6  （同上，F/E 同值）
  nk=F node=26 m=29 fs=26 te=26 end=33 ei=26 pos=0 np=2 isLH=0 iscb=0 iseb=0 pro=0 nsrc=0 nphi=1 tt=c
  nk=E node=26 m=29 （同上）
f177_graph_traversal_dfs_bfs       Graph::hasCycle          nbl=17
  nk=F node=3  m=NONE fs=3 te=10 end=17 ei=2 pos=0 np=0 isLH=0 iscb=0 iseb=0 pro=0 nphi=0 tt=n
  nk=E node=2  m=10 fs=3 te=10 end=17 ei=2  pos=0 np=2 isLH=1 iscb=0 iseb=0 pro=0 nphi=0 tt=c
```

⇒ 6 条中 5 条有静态候选，**全部由「位置」单条排除**（`m > fs ∧ m ≠ ei`，即候选落在帧内/帧后而非帧前），不依赖 `nphi`、`isLH` 等附加条件 ⇒ 位置条件本身就是分离器，判据可**字面**照 T1 既有 `lfi_is_join` 写；f177 的 `nk=E` 行另叠 `isLH=1`（双重排除），f067 的四行 `fs==te`（帧为空区间）且 `m` 带 1 条 PHI、`tt=c`（属下一层链的 cond 块，非本链 merge）。

**否证项（写死，防复发）—— 静态 IPD 不是动态回落的一般替代**：`lfi` 存在的 14 个 `T1-JOIN` 事件里，`IPD(候选) == 动态 lfi` 只在 **1 个事件**成立（`f124 ContainerOrchestrator::autoscale`，`nk=F`，`m=3==lfi`，其余 `pro=1` 是「动态已消费」的正常状态）；`nk=F` 其余 6 条、`nk=E` 全部 5 条（另有 2 条 `m=NONE`）**不等值** ⇒ **禁止**把路线 ③ 写成「用静态 IPD 替换既有 `lfi` 回传」，只允许写成**`lfi==null` 时的兜底支**（新增 `else if`），既有动态机制一字不动。

**T3 侧定面（不落地）**：`T3-PRE` 与 `T3-POST` **各** 48 条语料读数（两侧合计 96），**五条件真 = 0（96 条全 0）**；且 `lfi` 覆盖率极低（**每侧** 48 条中仅 4 条非 `NONE`）⇒ T3 新增消费者在语料上**既无命中面**，红形（形 7）在该站点又**没有静态候选**（`m=NONE`）⇒ 落地收益 = 0、风险面 ≠ 0 的可证明性 = 0 ⇒ **本轮结论：路线 ③ 只在 T1 侧落地，T3 侧不落地**。

**据读数写成的可落地判据（字面等于实测；行号为 R12 还原后干净树 `0e38b018…`/32796 重新 grep 实测）**：

```zig
// 站点实测（还原后）：:8865 `if (self.last_loop_fallthrough_idx) |lfi| {`
//                      :8871–:8876 五条件 lfi_is_join（位置二选一 ∧ 多前驱 ∧ 非循环头 ∧ 非 cond ∧ 非 exit）
//                      :8877–:8881 消费动作（merge_bi / processed.remove / 两标志清零）
//                      :8884–:8890 lsrc 的 PHI 物化块 —— 兜底支不得复制此块
// 落地形态 = 为 :8865 这个 if 追加 else 兜底支（原支一字不动）：
//   前置  = 走到 else 即 last_loop_fallthrough_idx == null
//   候选  = else_bi（本 cond_br 的 else 目标）；else_bi == null 则整支跳过
//   谓词  = findChainMergeByPostDom(func, else_bi) 存在 ∧ 五条件逐条与 :8871–:8876 同形（把 lfi 换成 m）
//   动作  = merge_bi = m; _ = processed.remove(m);
//           self.return_generated = false; self.break_generated = false;
//   禁止  = 任何 PHI 物化（实测该 m 块 nphi=0 且帧内 nsrc=0 ⇒ 无边可物化，写了就是无据代码）
//   不做  = 不读不写 last_loop_fallthrough_* 两字段（兜底支不制造新的隐式状态）
```

**预期与验收（这是预测，不是实测）**：形 9 命中 ⇒ 九形门 `same=7` → **`same=8 differs=1`**（残留 = 形 7 单形）；D 旁门、17 形、RC-4、RC-5、do-while、ref001、硬零漂移、官方 68、巡检、抽查、`zig build test` 全门必须逐字等于当前登记基线。**落地前状态**：R12 插桩已全删，代次回到 `0e38b018…`/32796 行（见 §3.17.2 收尾复验）。

#### 3.17.2 R12 还原后收尾复验（2026-10-05，干净树 `0e38b018…`/32796 行）

**插桩零残留四项（还原后立即实测）**：`md5` = **`0e38b018b24b9ba0aa358f8d26a7f012`**、`wc -l` = **32796**、`grep -c 'S13R12'` = **0**、`grep -c 'probeR12Node'` = **0**、`git diff HEAD --numstat -- src/aot/native_linker.zig` = **`385 30`**（逐字等于 R9-B 落地记录）⇒ 还原为**逐字节回到落地批代次**，非近似。

**干净重建**：`timeout 560 zig build` → **rc=0 / 63.80s**（user 61.70s）。

**十二道门复跑（串行，禁并发编译；G1–G7 于重建后立即单跑，G8–G12 由一条串行链依次释放编译窗口）**：

```text
G1  c006 九形门        C006_TL_GATE_DONE total=9 same=7 differs=2      ← 红点仍 = 形7(fncontext)/形9(ifarm)，输出签名逐字同基线
G2  c006 D 旁门        C006_D_GATE_DONE  total=2 same=2 differs=0
G3  c005 十七形        PROBE_DONE        total=17 same=17 differs=0
G4  c005 RC-4 诊断门   RC4_PROBE_DONE    total=4 same=3 differs=1      ← 唯一红点 = ref003_crash_attr_tmp rc=139（REF-003，非本族）
G5  c005 RC-5 合串     IDENTICAL|c005_rc5_merge_loss_tmp|rc=0
G6  c005 do-while      DOWHILE_PROBE_DONE total=2 same=2 differs=0
G7  ref001             PROBE_DONE        same=1 differs=3              （逐字等于 2026-09-30 登记基线）
G8  冻结基线漂移（硬零门）DRIFT_DONE total=68 ok=68 diff=0 notemp=0 norow=0   ⇒ 基线**不需重冻结**
G9  官方 harness       TOTAL 68 / PASS 67 / FAIL_COMPILE 0 / FAIL_RUNTIME 0 / FAIL_DIFF 0 / SKIP 1（SKIP 仍为 f004，PHP 解释器自身 exit=255）
G10 编译期确定性巡检    SWEEP_DONE        total=68 mismatch=0 notemp=0
G11 冻结基线抽查       SPOT_DONE         ok=5 bad=0
G12 zig build test     RC=0；Build Summary: 21/21 steps succeeded; 326/326 tests passed
```

**G12 口径修正（相对 §3.16.1 的方法缺陷）**：本轮直接 `timeout 560 zig build test --summary all` 并**从命令自身取 rc**，不再用 `| tail -3` 摘行 ⇒ 同时拿到 `RC=0` 与 summary 行（§3.16.1 记录的「幻影 failed command」问题源于旧的 tail 摘行法，非测试失败）。

⇒ **十二道门逐门等于 R9-B 落地基线** ⇒ R12 的 105 行只读插桩零残留复证完成；**本轮不产生落地批次**，工作区停在 `0e38b018…`/32796（RC-5+A+D+R9-B 四批未提交）。**已备好的落地物**：§3.17.1 末的 T1 兜底支判据（站点 `:8865`、五条件 `:8871–:8876`、动作 `:8877–:8881`、排除 `:8884–:8890`）＝ 字面等于实测，等老铁点头即可编码。

### 3.18 路线 ③ T1 兜底支落地批实测 = **第八次否证，性质「判据正确但动作惰性」**（2026-10-05，老铁授权「现在落地 T1 兜底支」）

**落地物（字面照 §3.17.1 判据编码）**：`src/aot/native_linker.zig` 在 `:8865` 的 `if (self.last_loop_fallthrough_idx) |lfi|` 追加 `else if (else_bi) |ei_fb|` 兜底支 —— 候选 `= try self.findChainMergeByPostDom(func, ei_fb)`，谓词 = 与 `:8871–:8876` **逐字同形**的五条件（`lfi` 换成 `m`），动作 = `:8877–:8881` 的四句（`merge_bi = m` / `processed.remove(m)` / 清 `return_generated` / 清 `break_generated`），**不含 PHI 物化**、**不读写 `last_loop_fallthrough_*`**；原动态支一字未动。

**代次戳（规约 (b)）**：干净基线 = 提交代次 `0e38b018…`/32796（HEAD `497edc6`）；落地批 = md5 **`602d809b56092a12d852b3f5f884a165`**、**32817 行**、`git diff HEAD --numstat` = **`21 0`**（纯插入）；取证插桩代次 = md5 `4208c39a5b055f91f09122d00c89a14b`、**32831 行**（`+14` 行 stderr 打印，`std.debug.print` 不入 `writer`）。`timeout 560 zig build` → **rc=0**（落地批 1:09.74 total，插桩批 rc=0）。

**实测三问（全部为读数，非推断）**：

1. **兜底支是否触发？触发面是否与 R12 判定一致？—— 一致。** 九形门在插桩代次的 `[R13-FB]` 读数：**只有形 9** 有读数，其余 8 形（含 7 个绿形）**0 读数** ⇒ 与 R12「红面 1 事件 / 绿面 0 / 语料面 0」逐字吻合。形 9 三行原文：

```text
[R13-FB] enter ei=2 blk=4 fs=0 end=9
[R13-FB] m=3 pos=1 np=3 isLH=0 iscb=0 iseb=0 pro=0 join=1
[R13-FB] FIRED merge_bi=3
```

   **口径更正（写死）**：`pos=1` 由**帧前**析取支 `m < blk_i`（`3 < 4`）成立，**不是** `m == ei_fb`（`ei_fb=2`）⇒ §7 R12 行「`T1-NULL nk=E` 行 `IPD(ei)=3` 使 `pos=1`」在此精确化：候选节点取 `ei` 是对的（`IPD(fs)=6` 被 pred/processed 双否），但位置条件靠「排在臂起点之前」这一支满足。

2. **触发之后发射变了吗？—— 几乎没变。** 两代次各编译形 9（`--compile --optimize=release-fast --no-debug-info` + `ZIGPHP_AOT_KEEP_TEMP=1`）取 `main.zig`：均 **1510 行**，md5 `c079ef6bc571ab6c733ce68b5a5e637f`（HEAD）vs `5819b4a34ba6aacc3a0fdd97609d167a`（落地批），`diff` 实测 **只有 1 行注释**（`:419` `// Cleanup: release all allocated values` → `// Cleanup`）；**运行时 stdout 逐字不变** = `T9 hit=3 sum=3 T9 b2 T9 else`（PHP 真值 `T9 hit=3 sum=3`）。⇒ 九形门在落地批代次仍 **`C006_TL_GATE_DONE total=9 same=7 differs=2`**，红点仍 = 形 7/形 9 ⇒ **§3.17.1 末「预期 `same=8 differs=1`」被实测否证**（该处当时已标注「预测，不是实测」）。

3. **为什么惰性？—— 动作在行走之后，帧界在行走之前。** 本帧上界 `then_end` 于**递归行走之前**由 `:8837–:8854` 求出：形 9 读数 `ei_fb=2 < blk_i=4` ⇒ 第一析取支不采，`else_branch_start` 缺失或不大于 `blk_i` ⇒ `then_end = end_idx = 9`；随后 `:8859` 的 `generateLabelDrivenBlockRange(writer, func, blk_i=4, then_end=9, …)` **已把兄弟臂块 5..8 线性吞进本臂并发射成顺序语句**（= C 类症状：臂间互斥丢失）。兜底支在行走**返回之后**才改判 `merge_bi`，只能决定「帧之后 merge 内容在哪发」，**无法撤回已发射的臂体** ⇒ 对形 9 **必要不充分**。

**结构性死锁结论（本族第八条，同时划出路线 ③ 的边界）**：`last_loop_fallthrough_idx` 由被派发的循环生成器**在行走过程中**写下 ⇒ 「本臂有无动态回落」只在行走完成后**才可知**；而阻止吞并必须在**行走之前**收窄 `then_end`。⇒ **任何以 `lfi == null` 为前置的兜底支都修不了形 9**；要在行走前拿到收口目标，只有 §7 路线 ③ 的**完整形态**（`generateLabelDrivenBlockRange` 返回「帧停止块」并回传给调用层；实测波及 = 该函数调用站点 **94 处**；若改用 `self` 字段传出则须为递归做 save/restore = §3.11 的隐式状态风险），或行走前的**结构**界臂判据（已被 R5 的 PC（`inh=0`）与 R11 的 `teA`/`teB`（35/35 零信息增益、语料面 18/15）两度否证）。

**撤销与复验（实测）**：落地批与插桩批全部撤销，`src/aot/native_linker.zig` 回到提交代次 —— `md5 = 0e38b018b24b9ba0aa358f8d26a7f012`、`git status --porcelain -- src/aot/native_linker.zig` **空**；撤销后 `timeout 560 zig build` rc=0，九形门复跑 **`total=9 same=7 differs=2`**，两条红点签名（`DIFF|c006_tl_fncontext_loop_tmp|php=[T7 hit=3 sum=3 ]|aot=[T7 branch3 ]`、`DIFF|c006_tl_ifarm_loop_tmp|php=[T9 hit=3 sum=3 ]|aot=[T9 hit=3 sum=3 T9 b2 T9 else ]`）与 §3.17.2 G1 登记值逐字相同 ⇒ 工作区与 HEAD `497edc6` 一致，未留下任何无功能效应的代码。

**留档判据（防复发）**：本条否证**不推翻** R12 的两条正面读数 —— 判据的**触发面**（红 1 / 绿 0 / 语料 0）与「候选节点取 `ei`」均成立；被推翻的是「T1 消费点的事后 `merge_bi` 交还足以修形 9」这一**动作**假设。⇒ 后续若再攻形 9，只允许从**行走前的帧收口**（路线 ③ 完整形态，94 站点波及）或**新机制**（形 7 同属此列）入手；**禁止**再把任何「行走后消费点」的改判当作形 9 的修法。

### 3.19 R14 影子轮：「帧内循环派发返回即停走」的 for/while 侧外扩 = **第九次否证**（2026-10-05，结案）

**问题来源（源码级不对称，非推测）**：`generateLabelDrivenBlockRange` 的行走循环里，四个循环派发点在「子生成器返回后」的处理**不一致** —— 只有 `foreach_cond_` 分支带「停走交还」规则（`defer_loop_fallthrough` ∧ `last_loop_fallthrough_idx` 非空 ∧ `lfi < loop_head_idx or lfi < range_start` ⇒ `break`，当前树实测 `:7471–:7478`），`for_cond_` / `while_cond_` / `while_body_` 三处派发返回后**只 `continue`，无停走**。形 9 臂内是 `for` ⇒ 假设「把 foreach 规则镜像到 for/while 即修形 9」。

**预登记接受条件（插桩前写死）**：可落地 ⟺ `stop=1` 命中红形（至少形 9）**∧** 68 语料 `stop=1` 事件 **0**；语料面 > 0 ⇒ 否证并登记命中脚本与字段。

**插桩口径**：6 枚 `std.debug.print`（全部走 stderr、不经 `writer` ⇒ 发射中性由基线自证）：`[R14-W]` 行走入口（`fs/rs/en/i/lbl/defer/rg/bg`）、`[R14-FE]` foreach 既有停走（含 `stop` 字段）、`[R14-FOR]/[R14-WHC]/[R14-WHB]` 三处**反事实**停走（**只打印不 `break`**）、`[R14-FORX]` for 派发返回后的**门状态**（`defer`/`haslfi`/`lfi`，无条件打印）。插桩代次行数 32802（+5）与 32803（+FORX），其 md5 **未留档**（插桩代次不回收，仅还原代次需校验）；还原代次实测 `md5 = fbe6382a2e0904b6740d771b88c409c7`、**32797 行**、`grep -c R14` = **0**、`git diff --numstat` = `5 4` 且 9 行改动**全为注释**（= #74 锚点卫生批，仍**未提交**）。

**实测读数（79 脚本 = 68 语料默认档 + 九形 + D 两形，门同档 release-fast）**：

| 项 | 读数 |
|---|---|
| 中性证明 | `R14_SHADOW_DONE total=79 hit_scripts=6 compile_fail=0 drift_ok=68 **drift_diff=0** drift_notemp=0 norow=0` ⇒ 插桩对 68 语料 `main.zig` 逐字节零改动 |
| 打印总量 | `[R14-W]` 204 条；`[R14-FE]` 10 条（**全部 `stop=1`**，6 脚本：f051/f056/f095/f102/f117/f124）⇒ 即 RC-4/RC-5 已拥有的 foreach 活规则，非新增面 |
| 反事实面 | `[R14-FOR]` 全语料 + 全探针 **仅 1 条读数**，且该条即 `stop=1`：`[R14-FOR] lbl=for_cond_6 fs=4 rs=4 lh=4 i=3 en=11 lfi=3 stop=1`，脚本 = **f124_container_orchestrator_pod_service_autoscale（冻结 PASSING 语料）**；`[R14-WHC]` / `[R14-WHB]` **0 条读数** |
| 红形面 | 11 枚 c006 探针（含形 7 `fncontext_loop`、形 9 `ifarm_loop`）的 `FOR/WHC/WHB` 读数 **全为 0** |

**判定 = 双否证**：接受条件两半**同时不成立** —— ① 红形面上该规则**一次都不触发**（镜像后对形 9 零效应）；② 唯一触发点在 PASSING 语料 f124（镜像后是真实漂移）。⇒ 「镜像 foreach 停走规则」**不落地**。

**门状态定位（`[R14-FORX]`，为什么红形不触发）**：for 派发返回后的 `defer`/`lfi` 实测 ——

```text
形 9  c006_tl_ifarm_loop_tmp   [R14-FORX] lbl=for_cond_4 fs=4 rs=4 lh=4 i=7 en=9 defer=1 haslfi=0 lfi=999999
形 1  c006_tl_shape1_tmp       [R14-FORX] lbl=for_cond_7 fs=6 rs=6 lh=6 i=9 en=9 defer=0 haslfi=0 lfi=999999
形 4  c006_tl_elseif_loop_tmp  [R14-FORX] lbl=for_cond_7 fs=6 rs=6 lh=6 i=9 en=9 defer=0 haslfi=0 lfi=999999
形 8  c006_tl_two_elseif_loop  [R14-FORX] lbl=for_cond_10 fs=7 rs=7 lh=8 i=11 en=11 defer=0 haslfi=0 lfi=999999
```

⇒ 停走谓词在 for 侧**无输入**：`last_loop_fallthrough_idx` 恒为 `null`（本族 8 个 for 形全为 `haslfi=0`，其中仅形 9 返回后 `defer=1`）。形 9 的 `for` 子生成器返回 `i=7` 而帧上界 `en=9` ⇒ 行走随即继续吞 `i=7 if_then_8`、`i=8 if_else_9` 两兄弟臂（= C 类症状本体）。

**由此产生的正面线索（登记，尚未取证）**：R13 的死锁结论是「消费点在行走之后」；本轮读数显示，形 9 的**停走动作本身在帧内**（派发返回后、行走继续前），若 `lfi` 被记录则可早停 —— 即形 9 的卡点从「消费点时机」前移为「**for 侧记录缺失**」。IR 证据支持其可达性：形 9 的循环出口回边指向 `if_merge_2`（索引 3 < `loop_head_idx=4`），若记为 `lfi` 则该谓词成立。⇒ 下一步只读轮（R15）应在 `generateForFromLabels` 内部打印入口 `defer` 值、各 `last_loop_fallthrough_idx` 写入站点的到达情况与求解出的 `exit_idx`，定位「为何为 null」；**约束不变**：`defer_loop_fallthrough` 的置位面禁止外扩（护 f161 缺陷B / xp8 幻影输出），且 `self` 静态字段的 save/restore 语义须先实测再谈改。**该线索仅为待取证假设，非修法**；发射侧任何改动仍待老铁点头。

**还原与十二腿复验（实测 2026-10-05，串行、无并发编译）**：`cp /private/tmp/nl_r14_backup.zig` 还原 ⇒ md5 `fbe6382a2e0904b6740d771b88c409c7`、32797 行、`grep -c R14` = 0、`git diff --numstat` = `5 4`（9 行全为注释 = #74 批完好，**未提交**）；干净 `timeout 560 zig build` rc=0 后逐门：**九形** `C006_TL_GATE_DONE total=9 same=7 differs=2`｜**D 旁门** `total=2 same=2 differs=0`｜**C005 十七形** `PROBE_DONE total=17 same=17 differs=0`｜**RC-4** `RC4_PROBE_DONE total=4 same=3 differs=1`（唯一红点 = `ref003_crash_attr_tmp rc=139`，归 REF-003）｜**RC-5 合串** `IDENTICAL`｜**do-while** `DOWHILE_PROBE_DONE total=2 same=2 differs=0`｜**ref001** `PROBE_DONE same=1 differs=3`（**逐字等于 2026-09-30 登记基线**，差异全落属性引用侧）｜**硬零漂移** `DRIFT_DONE total=68 ok=68 diff=0 notemp=0 norow=0`｜**官方 68** `TOTAL 68 / PASS 67 / FAIL_COMPILE 0 / FAIL_RUNTIME 0 / FAIL_DIFF 0`｜**编译期确定性巡检** `SWEEP_DONE total=68 mismatch=0 notemp=0`｜**基线抽查** `SPOT_DONE ok=5 bad=0`｜**`zig build test --summary all`** `21/21 steps succeeded; 326/326 tests passed` rc=0。⇒ 还原代次与提交代次 `497edc6` 行为等价，R14 插桩零残留。

**流程教训（登记）**：巡检腿首次被我 `run()` 里的 `timeout 1200` 截断成 `rc=124`（**不是**失败读数），须按该脚本实测耗时放宽到 `timeout 2400` 单跑复核 —— 已实测 `SWEEP_RC=0`。**门链包装上限不得低于被包脚本的实测耗时**，否则「超时」会被误读成「巡检不绿」。

### 3.20 R15 影子轮：for 侧「exit 块一跳回落目标」记录侧取证 = **预登记判据满足（首次非否证）**（2026-10-05，结案）

**轮次定位**：取证 §3.19 末登记的正面线索（形 9 卡点 = 「for 侧记录缺失」，非「消费点时机」）。预登记判据（写在插桩之前）：**`HOPQ`（`defer=1 ∧ tk=0 ∧ hoplt=1`）在红形面命中 ∧ 语料面 0 事件 ⇒ 候选进入落地评审；语料面 > 0 ⇒ 第十次否证并逐脚本登记**。

**插桩口径**：1 枚探针 `[R15-X]`（`generateForFromLabels` 出口判定区入口，干净代次 `:14923` 之前）打印 13 字段（`lbl/ci/bi/li/ei/elbl/en/defer/inb/tk/hop/hlbl/hoplt/nlfi`），其中 `tk` 为终止符类别（0=`br` 1=`cond_br` 2=其他 9=null，**按 `ir.zig:568` 的 `Terminator` 变体实测写就**，首版误用 `.abort` 已纠）、`hop`/`hlbl` 为 `.br` 目标按指针反查所得索引与标签（找不到记 `999999/NONE`）；另 9 枚 `[R15-RT] site=N`（九个 `return` 站点各一，其中 `:13345`/`:13364` 两早退站点用「仅 `ci/en/defer/inb/nlfi`」的精简模板，防 ReleaseSafe 读 `undefined` 即 panic）。代次 `fbe6382a`/32797 → **32825 行**（净插桩 +28）。**全部走 stderr，无一字进 `writer`。**

**中性双证（实测）**：`R15_SHADOW_DONE total=79 hit_scripts=39 compile_fail=0 drift_ok=68 drift_diff=0 drift_notemp=0 norow=0` ⇒ 68 语料默认档（`--compile --no-debug-info`）的 `main.zig` 行数+md5 与冻结基线**逐字节等值**。**口径差异如实登记**：本轮未在插桩代次上跑九形门 stdout 对比（R9–R12 曾跑），形面属主读数取自探针行本身；九形门读数见本末「还原与十二腿门链」。

**全量读数（150 条 `[R15-X]` 事件，14 个等价类）**：

| cond 标签族 | hop 标签族 | `defer` | `tk` | `hoplt` | 事件数 |
|---|---|---|---|---|---|
| `for_cond_N` | `NONE` | 0 | 2（其他） | 0 | 78 |
| `for_cond_N` | `for_cond_N` | 0 | 0 | 1 | 25 |
| `for_cond_N` | `for_cond_N` | 0 | 0 | 0 | 13 |
| `for_cond_N` | `NONE` | 0 | 1（`cond_br`） | 0 | 11 |
| `for_cond_N` | `if_merge_N` | 0 | 0 | 1 | 7 |
| `for_cond_N` | `foreach_cond_N` | 0 | 0 | 0 / 1 | 4 / 3 |
| `for_cond_N` | `while_cond_N` | 0 | 0 | 0 / 1 | 3 / 2 |
| `for_cond_N` | `for_loop_N` | 0 | 0 | 1 | 1 |
| **`for_cond_N`** | **`if_merge_N`** | **1** | **0** | **1** | **1 ← 唯一 HOPQ** |
| `for_cond_N` | `NONE` | 1 | 2 / 1 | 0 | 1 / 1 |

**三条判定性读数**：

1. **`HOPQ_TOTAL=1`**，唯一事件 = **红形 9**：`[R15-X] lbl=for_cond_4 ci=4 bi=5 li=5 ei=6 elbl=for_exit_7 en=9 defer=1 inb=1 tk=0 hop=3 hlbl=if_merge_2 hoplt=1 nlfi=0`，同脚本 `[R15-RT] site=9 ... defer=1 inb=1 nlfi=0`（经通用路径 `:15026` 返回、`lfi` 留空）⇒ **与 §3.19 的 `[R14-FORX]` 独立复证一致**。绿形九枚全部 `HOPQ=0`；语料 68 枚全部 `HOPQ=0`。
2. **语料的 `defer=1` 事件在新支「结构不可达」**：全 79 脚本仅 3 条 `defer=1`，除形 9 外为 `f124`（`ei=3 < ci=4`，`tk=2`）与 `f161`（`ei=8 < ci=9`，`tk=1`），两者都由**更靠前**的 `:14923` 直接位置支接走 ⇒ 返回站点读数为 `[R15-RT] site=5 ... nlfi=1`（已记录并 `return exit_idx`）。即新支的插入点（`:14975`/`:14977` 之间）在这两条语料路径上**根本不会被执行**，中性证据比「谓词为假」更强一层。
3. **窄度来源 = `defer` 单条件**：`tk=0 ∧ hoplt=1` 但 `defer=0` 的事件共 **38** 条（hop 为 `for_cond_N` 25、`if_merge_N` 7、`foreach_cond_N` 3、`while_cond_N` 2、`for_loop_N` 1；另有 13 条 `hop=for_cond_N` 属 `hoplt=0` 的前向边，不计入）⇒ 谓词里 `defer` 是唯一收敛力，与「只在臂内联上下文细化目标」的设计意图一致，也再次印证坑 5（置位面禁止外扩）。**附带实证坑 3**：该 38 条按 hop 标签分类为 **31 条循环标签**（`for_cond_N` 25 + `foreach_cond_N` 3 + `while_cond_N` 2 + `for_loop_N` 1）+ **7 条 `if_merge_N`**，而 `isLoopHeadLabel`（实测 `:25641–:25652`）的口径含 `for_loop_`/`foreach_increment_` ⇒ **82% 的一跳目标是循环标签**。⇒ 若将来 `defer` 面扩大，`isLoopHeadLabel` 排除支必须存在（同时与消费者 `:8874` 同口径）。

**形 7 复证**：`c006_tl_fncontext_loop_tmp` 的 `[R15-X]` 事件数 = **0**（其 `for` 子生成器从未走到出口判定区）⇒ 本候选覆盖面 = **形 9 一形**，验收目标 `same=8 differs=1` 不变（形 7 仍归 §3.10 的臂守卫坍缩命题）。

**判定**：**预登记判据满足 ⇒ R15 不是否证** —— 开店以来第二个「读数支持落地」的候选（首个为 R9-B）。成对候选（§4.7 改动一 + 改动二，模板已预写）具备：红面 1 / 绿面 0 / 语料面 0、下游消费者已实测可接住（R13 `join=1`）、机制先例已存在（foreach `:12962–:12972` + `:7471–:7477`）、坑 1/坑 2 经实文复核消解。**剩余唯一未实测项 = 坑 4（交还后兄弟臂由既有乱序双臂模板发射）**，只能在落地批以九形门 stdout 判定。**发射侧源码本轮零改动**，等老铁「落地」指令。

**还原与十二腿门链（实测 2026-10-05）**

*还原口径（字节级自证，非「行数相同」弱证）*：

| 项 | 实测 | 判定依据 |
|---|---|---|
| 插桩拆净 | `grep -c 'R15T' src/aot/native_linker.zig` = **0** | 影子轮的全部读数标签以 `R15T` 为前缀 ⇒ 计数 0 即无残留 `std.debug.print` |
| 源码回到干净代次 | md5 **`fbe6382a2e0904b6740d771b88c409c7`**、**32797 行**；`git diff --numstat` = **`5 4`**（仅剩 #74 纯注释批） | 与影子轮开始前的整份备份 `/private/tmp/nl_r15_backup.zig` **md5 逐字节相同** ⇒ 还原是 byte-identical，不是「看起来一样」；该备份本轮保留作对照，属一次性取证资产，门链收尾后随 `r15_*` 一并清理 |
| 模板未动 | `src/aot/runtime_lib_template.zig` md5 **`008b7b639f1069cb73e443064e115ed1`**（与轮前同值） | 批内禁改 `runtime_lib_template.zig` 纪律维持 |
| 二进制代次归属 | 漂移腿 `DRIFT_DONE total=68 ok=68 diff=0 notemp=0 norow=0` | 68 语料 `main.zig` 行数+md5 全等冻结基线 ⇒ 门链所用二进制确实由**干净代次**重建，而非残留插桩态 |

*十二腿读数（串行、无并发编译；完成时刻 2026-10-05 23:49:48，链尾标记 `CLOSEOUT_DONE`，十二腿 rc 全 0）*：

| # | 腿 | 命令 | 实测读数 | 与登记基线 |
|---|---|---|---|---|
| 1 | 九形等值门 | `c006_tl_probe_run_tmp.sh` | `C006_TL_GATE_DONE total=9 same=7 differs=2`（红点 = `c006_tl_fncontext_loop_tmp` 形 7、`c006_tl_ifarm_loop_tmp` 形 9） | ✅ 逐字一致（形 9 仍红 ⇒ 本轮判据面未动发射） |
| 2 | D 批双臂门 | `c006_d_probe_run_tmp.sh` | `C006_D_GATE_DONE total=2 same=2 differs=0` | ✅ |
| 3 | 十七形门（CODEGEN-005） | `c005_probe_run_tmp.sh` | `PROBE_DONE total=17 same=17 differs=0` | ✅ |
| 4 | RC-4 诊断门 | `c005_rc4_probe_run_tmp.sh` | `RC4_PROBE_DONE total=4 same=3 differs=1`（唯一红点 `ref003_crash_attr_tmp` `rc=139` ⇒ 归 REF-003 的 W3） | ✅ |
| 5 | RC-5 八形合串 | `c005_rc5_probe_run_tmp.sh` | `IDENTICAL\|c005_rc5_merge_loss_tmp\|rc=0`，`RC5_PROBE_DONE` | ✅ |
| 6 | do-while 门 | `c005_dowhile_probe_run_tmp.sh` | `DOWHILE_PROBE_DONE total=2 same=2 differs=0`（F-I/F-J） | ✅ |
| 7 | REF-001 探针门 | `ref001_probe_run_tmp.sh` | `PROBE_DONE same=1 differs=3`（`obj_prop_ref_control_probe_tmp`/`obj_prop_ref_rehash_probe_tmp` 等按 §3.1 修订口径判定，D1 仍待裁） | ✅（与 §7.1 登记口径一致，非新增差异） |
| 8 | 基线漂移 | `c005_full_drift_tmp.sh` | `DRIFT_DONE total=68 ok=68 diff=0 notemp=0 norow=0` | ✅ 语料零漂移 ⇒ **未重冻结基线** |
| 9 | 官方 68 回归 | `scripts/regression_test_720.sh` | `TOTAL 68 / PASS 67 / FAIL_COMPILE 0 / FAIL_RUNTIME 0 / FAIL_DIFF 0 / SKIP 1`；`regression_failures.tsv` 仅 `SKIP\|f004_oop_deep_inheritance_magic.php\|PHP_error_exit=255` | ✅ 与 RC-4/RC-5/CODEGEN-006 各批登记值逐字相同 |
| 10 | 确定性巡检 | `f12_determinism_tmp.sh` | `SWEEP_DONE total=68 mismatch=0 notemp=0`（68 脚本各编译两次，`main.zig` 行数+md5 逐次相等）| ✅ 逐字一致 |
| 11 | 基线抽查 | `s7_baseline_spotcheck_tmp.sh` | `SPOT_DONE ok=5 bad=0`（抽查含 `f067_json_parser_schema_path_diff` `47364\|ad2f742d…`、`f113_distributed_consistenthash_vectorclock_quorum` `104334\|dab7d3a6…`） | ✅ |
| 12 | 单测 | `zig build test --summary all` | `Build Summary: 21/21 steps succeeded; 326/326 tests passed`，rc=**0**；其中一行 `failed command: ./.zig-cache/o/55e2…/test … --listen=-` 为 `ci_integration.test.CIRunner` 自调二进制的既有 stderr 泄漏（字节位置与批前基线全同，该二进制单跑报 `All 3 tests passed`），不计失败 | ✅ |

**R15 结案（十二腿全等值 ⇒ 本轮判据面零外溢）**：`C006_TL_GATE_DONE same=7 differs=2` 与漂移 `diff=0` 两条合起来构成「影子轮中性 + 干净代次二进制」的双重自证，余十腿逐腿等于各批登记基线 ⇒ **R15 正式闭环，工作区停在 `fbe6382a`/32797（#74 纯注释批仍未提交），发射侧源码零改动。** 产物清理：`/private/tmp/r15_*`（插桩脚本、`r15_raw/` 聚合与 `.err`、`r15_closeout/` 十二腿日志与链脚本）已删；**唯一保留物 = `/private/tmp/nl_r15_backup.zig`** —— 原口径写的是「随 `r15_*` 一并清理」，此处按更强的保护理由更正为**保留至 #74 提交**：`git checkout -- src/aot/native_linker.zig` 会连未提交的 #74 注释批（`git diff --numstat` = `5 4`）一起抹掉，届时无其它还原源；该文件在 `/private/tmp` 内、不入库、不占仓库资产面。

### 3.21 R16 生成码侧只读复证：形 7 的实际形态 = **缺二级守卫 + 末臂整体丢失**，且其链**无 `if_merge_` 块**（2026-10-05，零插桩、零源码改动）

**取证方式（无任何写操作风险）**：直接用十二腿门链刚复验过的干净二进制 `./zig-out/bin/php-interpreter`（时间戳 22:49:11，代次归属由漂移腿 `diff=0` 自证）跑两件事 —— ① `ZIGPHP_AOT_KEEP_TEMP=1 --compile --optimize=release-fast --no-debug-info` 取生成码；② `--compile --dump-ir` 取 IR。**`native_linker.zig` 全程未改（`grep -c R16` = 0，md5 仍 `fbe6382a…`），产物用后即删。**

**症状复现（与九形门同判）**：AOT stdout = `T7 branch3`，PHP 真值 = `T7 hit=3 sum=3`。

**生成码逐行证据**（`main.zig` 行号属本次实测；函数 `@"c006_tl_f7"` 体 = `:39`–`:180`）：

| 位置 | 实测内容 | 判读 |
|---|---|---|
| `:131`–`:132` | `reg_4 = try runtime.php_identical(reg_2, reg_3);` + `if (reg_4.toBool()) {` | **一级链守卫在位**（真臂 `:133`–`:149`，假臂 `:150` 起） |
| `:159` | `reg_8 = try runtime.php_identical(reg_2, reg_7);` | 二级条件**算出但全文无消费者** ⇒ 实测「连 `if (` 都没有」，`reg_8` 仅在 `:175` 被 `release` |
| `:163` | `reg_9 = runtime.Value.initString(static_strings[6]);`（即 `"T7 branch3\n"`） | 二级**真臂体被无条件内联**进假臂位置 |
| `:176` / `:179` | `return ... reg_9 ...;` / `unreachable;` | 假臂位置以「无条件 return」收口，函数尾落 `unreachable;` |
| 函数体全文 | `grep` 实测 `for \|while` 命中 **0**；`static_strings[10..12]`（`"T7 hit="`、`" sum="` 等，常量表 `:19`–`:20` 仍在）**在函数体内零引用** | ⇒ **`if_else_4` + `for_cond_7` + `for_body_8` + `for_exit_10` 四个块整体未发射**（不是"臂体在但串跑"，是**丢失**） |

**IR 侧语义完全正确**（同一实测）：`entry → br(cond %4) if_then_0, if_else_1`；`if_else_1 → br(cond %8) if_then_3, if_else_4`；`if_else_4 → br for_cond_7`；`for_exit_10 → ret` 三条臂各自 `ret` 收口。⇒ 缺陷在**发射侧**，与 IR/optimizer 无关（与本单既有结论同向）。

**结构判别（13 枚 `c006_tl_*` 探针全量扫，本轮唯一新读数）**：按块标签计数 `if_merge_*` —— **`c006_tl_fncontext_loop`（形 7）= 0**，其余 **12 枚全部 = 1**（含另一红形 `c006_tl_ifarm_loop` 形 9）。⇒ 形 7 的 `if/elseif/else` 链**没有共享 merge 块**（三臂全以 `ret` 收尾），这正是 R9/R10 在该形读到 `IPD=null`、以及 `merge_bi` 交还机制「无对象可交」的**根因实测**；不是判据选错，是**该形根本没有 merge**。

**对 §3.10 的更正（必须与本节同读）**：§3.10 原文「B（4/7）与 C（9）… 生成码里**三条臂的臂体一块不少**」—— 本轮实测**对形 7 不成立**（末臂连体带循环整体丢失），对形 4/9 是否成立仍按 §3.10 当时读数为准。**形 7 应改读为「缺二级守卫 + 末臂丢失」的双缺陷**，不得再按 C 类单因（区间/串跑）判读；其候选机制回到 §4 表的 **A/D 类**（缺失派发）而非 B/C 类（区间语义），且因无 merge，`defer`/`lfi` 一族机制对其**天然无效**。

**判定**：R16 不产生落地批次、不产生新判据（本轮零插桩，只有生成码与 IR 的只读复证 + 一次 13 探针块标签计数）。

#### 3.21.1 R17 立项前提的只读复算：吞掉站点**早在 R8 就已定位**，原「五枚内联发射器」口径作废（2026-10-06，零插桩、零源码改动）

写 R17 提案之前，先把 R8/R8.1 的既有逐字读数（§3.11 `S09I`、§3.12 `S09N`）与本轮生成码证据对表，结果**推翻了 R17 的立项问题本身**：

| 交叉证据 | 读数 | 与 R16 生成码的一致性 |
|---|---|---|
| R8 `S09I` / R8.1 `S09N` 形 7 行 | `src=entry nti=3 nei=4 nmi=5(for_cond_7) cs18_end=8 end=8 ttag=`**`ret`** `ttgt=99999 etag=br etgt=5 narm=2 tproc=0 eproc=0` | 帧 `[3,8)` 走的是 `nested_then_idx` 兜底**线性摊平**调用（§3.11「路由一」），**不是**任何内联发射器 |
| 帧起点块 3 = `if_then_3`，终止符 = `ret` | 摊平帧先发射块 3 ⇒ `return_generated` 置位 ⇒ 行走器头部不可达检查（`:7449–:7453` `markReachableRestBlocks`）把 **4..7 整体吞标** | 精确解释 R16 三条实测：无二级 `if (`、末臂四块（含 for 子树）零发射、`static_strings[10..12]` 常量无引用 |
| R8-a 语料面（§3.11 表） | `f067 params_merge … ttag=`**`br`** `ttgt=9` / `f067 entry … ttag=`**`br`** `ttgt=5` | f067 与形 7 在 `ttag` 上**不同值** ⇒ R8-a 的「面 = 1」并非不可收窄 |

⇒ **结论一（否证 R17 原口径）**：形 7 的二级 `cond_br` **不是**被 `emitBlockInlinedWithPhiFrom` / `emitSpilledNestedIfMerge` 这五处吞掉的，而是被 §3.11 已归类的 **N/T3 兜底线性摊平 + `ret` 冒泡 mark-rest**（= §4 表「共因」放大器行的 else/elseif 侧同款）吞掉的。**该问题在 R8 已回答完毕，重装探针再问它是浪费一轮。**

⇒ **结论二（一条从未被测的合取，登记为待裁决假设，不是判据）**：R8.1 测过 `etag=br ∧ etgt<nti`（形 7 为假）与 `narm>=2`（判为巧合），P-a2 只加了 `etag` 方向，**`ttag`（本链 then 臂终止符类别）这一枚从未进入任何合取**。候选 = `R8-a 四条件 ∧ ttag=ret`。**其语料面目前 = 未知**（R8.1 的 `/tmp` 原始日志已按产物规约删除，不可凭记忆外推；`S09N` 语料 24 事件中 `ttag=ret` 的条数无记录）。与 R8.1 被判「对红形的拟合」的字段不同，`ttag=ret` 本轮**首次拿到机制解释**：`ret` 置位 `return_generated` 是行走器收口的**因**、末臂丢失是其**果** ⇒ 若面为 0，性质属「机制不变量」而非巧合。

**三条约束（不得越线）**：① 覆盖面**仅形 7 一形**（形 9 由 §4.7 候选承担、形 4 已绿）；② R10 测到形 7 的 `cls=V ∧ ge=1` 签名被 4 个通过脚本复现（f007/f026/f067_min_repro/f102×2），R11 测到其 T3 签名与 f026/f102 除函数名外逐字节全等 ⇒ **`ttag` 不在那两轮的字段集内**，故本轮既不宣布可二分、也不宣布不可二分，只宣布**未测**；③ 即便面为 0，**动作仍待定**（形 7 无回向 merge ⇒ 改走双臂模板后由谁收口未定，须与 §7 路线 ③ 完整形态同批裁决）。⇒ R17 重定义为「`ttag` 单字段面」窄探针轮（站点 = `S09N` 同处，一枚 tag、只读、stderr-only，**开轮前须先确认该站点在当前代次 `fbe6382a` 可复现原读数**），待老铁点头；登记入 §7 待裁决项 a′。

### 3.21.2 R17 开轮前置的只读实文核对（2026-10-06，零插桩、零编译、零源码改动）

上行的前置「须先确认 `S09N` 站点在当代次可复现原读数」**已以读源码方式当场完成**，故 R17 一旦点头即可直接插桩，无需再花一轮找锚点。

**站点定位（当前代次 `fbe6382a`/32797 实测行号）**：`S09I`/`S09N` 所在站点 = else 侧链处理器的 `nested_then_idx` 兜底摊平支。

| 锚点 | 现文 | 与 R8.1 读数字段的对应 |
|---|---|---|
| `:10178` | `} else if (nested_then_idx) \|nti\| {` |  binder `nti` = 读数 `nti`（形 7 = 3） |
| `:10179` | `if (!processed.contains(nti)) {` | 该支的进入守卫（R17 须在其**内侧**打印，否则复现不出进入次数） |
| `:10180` | `if (nested_merge_idx) \|nmi_raw\| {` | 读数 `nmi` 的来源 |
| `:10189–:10196` | `const nmi: usize = blk_p9: { … findChainMergeByPostDom(func, ei) … }` | **R9-B 落地块**（形 7 的 `cls=V` ⇒ 该块必回落 `nmi_raw`，见下） |
| `:10197` | `if (nmi >= nti) {` | 读数 `cs18_end`/`end` 所在支的进入条件 |
| `:10202` | `const cs18_end: usize = blk18: { … }` | 读数 `cs18_end`（形 7 = 8 = `end` ⇒ 走 `end_idx` 兜底） |
| `:10214` | `generateLabelDrivenBlockRange(writer, func, nti, cs18_end, …)` | **即「线性摊平」调用本身** ⇒ §3.21.1 结论一的落点 |
| `:10191` / `:10231` | `findChainMergeByPostDom(func, ei)` / `nt_blk.terminator` | `ei`（else 臂索引）与「块终止符可读」在此支已就地存在 ⇒ 读数 `nei`/`etag`/`etgt`/`ttag`/`ttgt` 全部可绑定 |

**字段可绑定性（逐字对照 §3.12 探针字段定义）**：`nei` ← `ei`、`ttag/ttgt` ← `func.blocks.items[nti].terminator`、`etag/etgt` ← `func.blocks.items[ei].terminator`、`narm` ← 在 `:10202` 之后对 `[nti, cs18_end)` 逐块比标签前缀 `if_then_/if_else_`、`tproc/eproc` ← `processed.contains(nti)`/`.contains(ei)`、`src` ← 当前函数名。**结论：S09N 的六个字段在当前代次全部可在同一支内取到，站点未迁移、未被删改。**

**相对 R8.1 插桩代次 `4f29ae2d`/32792 的唯一代码差异** = 本支新增了 `:10189–:10196` 的 `blk_p9` IPD 改判块（R9-B 批，`497edc6` 入库）。**「原五处未动」以 blame 实证，非断言**（HEAD `497edc6` 逐行 blame）：`:10178` = `77872d7c`（2026-08-29）、`:10179` = `64d3bba1`（2026-07-30）、`:10197` = `62fd6489`（2026-07-31）、`:10202`/`:10214` = `24634df2`（2026-09-28）—— **全部早于 R8.1** ⇒ 该五处从 R8.1 到当前代次一字未改；而 `:10180`（`if (nested_merge_idx) |nmi_raw| {`）与 `:10189–:10196` 同为 `497edc6`（R9-B 的替换行 + 内联块）⇒ R17 读到的 `nmi` 是**改判后**值。对形 7 而言该差异不改变读数：**推导**依据 = R10 在同一链节点实测 `cls=V`（IPD 结果为虚拟出口而非块，§3.15）⇒ `blk_p9` 的 `if (try … ) |m|` 不成立 ⇒ 必回落 `nmi_raw`（= 原 `nmi=5`）。**该等值属推导，非本轮新读数**，R17 开轮时须以实读复证（形 7 若 `nmi ≠ 5` 即说明站点语义已变，先停轮回填）。

**R17 落地要点（据本核对固化）**：探针插在 `:10179` 守卫**内侧**、`:10197` 之前（此位置 `nti`/`ei`/`nmi_raw`/`nmi` 均已绑定，且早于帧上界求解）；stderr-only、无一字进 `writer`；扫描面 = 68 语料 + 13 永久探针，按规约 (a) 以 `ttag=ret` 单字段先出**语料事件表**，再谈合取。**打印点分档（防假阴性）**：本轮只取 `ttag` ⇒ `:10197` 之前即可；但若要在同一行复现 R8.1 的**原六字段全行**，`cs18_end` 与 `narm`（定义域 `[nti, cs18_end)`）依赖 `:10202` 的帧上界求解 ⇒ 打印点必须移到 `:10202` 之后，否则这两枚恒 0/恒未定义，会把「站点未迁移」误判成「读数不符」。

**本轮（R16 + §3.21.1 + §3.21.2，任务 #83/#85）变更摘要文档**：`docs/changes/2026-10-06/形7生成码复证与R17立项复算_CODEGEN-006R16_2026-10-06_fbe6382a.md`。零源码改动自证（2026-10-06 实测）：`md5` 仍 `fbe6382a…`、`wc -l` = 32797、`git diff --numstat` = `5 4`（#74 纯注释批原样）、`grep -cE 'R15|R16|R17|S09|S1[0-3]' src/aot/native_linker.zig` = 0、`git status --porcelain | grep -c '^ D'` = 0、`.php` 零删除零修改 ⇒ **代次未迁移，上轮十二腿门链 12/12 读数继续有效，本轮不产生新的九形门读数**。

### 3.22 #81 落地批锚点与口径只读复验（2026-10-06，零插桩、零编译、零源码改动）

与 §3.21.2 对称：那轮为 #84 清掉开轮前置，本轮把 **#81（§4.7 成对候选）的落地锚点与逐字模板对当前代次实文复验**，使「落地」点头能直接换代码。**结论 = 锚点全部等值，但发现一条阻断项（3.22.3），故 §4.7 现稿不得逐字落地。**

**3.22.1 锚点复验（实文逐行，代次 `fbe6382a`/32797）**

| 组 | 锚点 | 实测现文 | 判定 |
|---|---|---|---|
| 记录侧插入界 | `:14925` / `:14935` | `self.last_loop_fallthrough_idx = exit_idx;` / `return exit_idx;`（直接位置支体首与收口） | 等值 |
| | `:14940–:14941` / `:14943` | `if (exit_block.terminator) \|term\| {` + `if (term == .cond_br) {` / `return exit_idx;` | 等值 |
| | `:14951` / `:14961` / `:14963` / `:14971` / `:14974` / `:14975` | `for_loop_` 前缀测试 / `if (self.in_cond_br_branch) {` / 该支 `lfi = exit_idx` / `return exit_idx;` / `return exit_idx + 1;` / 该支收尾 `}` | 等值（插入界 `:14975`↔`:14977` 成立） |
| | `:14977–:14981` | `try processed.put(exit_idx, {});` + 逐条发射 `exit_block` 指令 | 等值（坑 1 的「通用路径本就发射」成立） |
| | `:14996` / `:14999–:15003` / `:15004` / `:15005–:15010` / `:15009` / `:15018` / `:15021` / `:15026` | `.br => \|br_target\| {` / `target_is_loop_header` 五枚前缀 / 其进入 `if` / 指针反查循环 / `return error.TargetBlockNotFound;` / 派发调用 / `.br` 支收口 / `return exit_idx + 1;` | 等值 |
| 行走侧 | `:7446` / `:7449` / `:7452` / `:7453` | `while (i < end_idx) {` / `return_generated or break_generated` 测试 / `markReachableRestBlocks` / `return;` | 等值（坑 4 (i)「`break` 不落吞标」成立） |
| | `:7465` / `:7466` / `:7467` / **`:7471–:7477`** | foreach 测试 / `const loop_head_idx = i;` / 派发 / 停走七行（`defer` 测试 → `lfi` 取值守卫 → `lfi_w < loop_head_idx or lfi_w < range_start` → `break` → 三枚闭合） | 等值（抄写模板逐字可用） |
| | `:7482` / `:7483` / `:7484` / `:7485` | for 测试 / 派发（**实文无 `loop_head_idx`** ⇒ 改动二确为 +2 行）/ `continue;` / `}` | 等值 |
| | `:7488` / `:7495` | `while_cond_` 测试 / `while_body_` 测试 | **`§4.7` 末行原引 `:7494` 为 off-by-one**（`:7494` 是注释行），本轮已在 §4.7 就地更正 |
| helper 缝 | `:7429` / `:7430` / `:7431` / `:7432` | `warnEmptyElseBeforeUnreachable` 收尾 `}` / 空行 / `fn generateLabelDrivenBlockRange(` / `self: *Self,` | 等值；`armFallthroughStop` 全文件 grep **0 命中** ⇒ 名字可用 |
| 字段与签名 | `:281` / `:285` / `:290`；`:25641–:25652` | `last_loop_fallthrough_idx: ?usize` / `…_src_idx: ?usize` / `defer_loop_fallthrough: bool`；`isLoopHeadLabel(self: *const Self, label: []const u8) bool`（九枚前缀） | 等值 |
| 消费侧 | `:8837–:8854` / `:8855–:8856` / `:8858` / `:8859` / `:8865` / `:8884` | `then_end` 求解块（不动）/ 清 `lfi` 两行 / `defer = true` / 递归行走 / `if (self.last_loop_fallthrough_idx) \|lfi\| {` / `if (self.last_loop_fallthrough_src_idx) \|lsrc\| {` | 等值 |

**3.22.2 两条新实测口径（不推翻候选，仅收窄其成立方式）**

- **前缀集不对称（坑 3 的保守方向实证）**：`.br` 目标派发支自用的 `target_is_loop_header`（`:14999–:15003`）**只有五枚前缀**（`foreach_cond_`/`for_cond_`/`while_cond_`/`while_body_`/`do_while_body_`），而改动一排除所用的 `isLoopHeadLabel`（`:25641–:25652`）有**九枚**，宽出 `foreach_body_`/`foreach_increment_`/`for_body_`/`for_loop_` 四枚。⇒ 改动一的守卫**严格宽于**派发支自身：一跳目标落在这四枚上时，派发支不发（既有行为）、新支也不记 ⇒ 与今日**逐字等价**；落在 `while_body_` 一类时，新支被守卫挡掉，避免与 `:15018` 的递归派发双写 `lfi`。**结论：坑 3 的排除面不得收窄为五枚**，收窄即引入双写风险。
- **覆盖面 = 九个派发返回点中的一个**：`self.generateForFromLabels(` 全文件 9 个调用点 —— 仅 `:7483` 把返回值写回行走指针（`i = try …`），其余八处（`:7845`、`:11859`、`:11881`、`:14018`、`:14036`、`:15668`、`:15681`、`:16950`）为 `_ = try …` 弃返回值、并由各自的 `lfi` 消费块收尾（`:7853`、`:11926` 一类）。⇒ 改动一只影响 `generateForFromLabels` **内部**的记录，八处弃返回值站点会新看到非空 `lfi`（其既有 `== nei` 比较支可能新触发 PHI 物化）；改动二的停走只覆盖 `:7483`。**该风险面由 §3.20 的实测读数封闭**：`HOPQ` 谓词在 68 语料上命中 **0**（2 条 `defer=1` 均被更前的 `:14923` 提前接走）⇒ 语料上记录支不可达 ⇒ 八处消费点看到的 `lfi` 不变。落地批的硬零漂移门即此论证的复测。

**3.22.3 阻断项：改动二逐字落地会重触发 R14 的 f124 反例**

R14 的 `[R14-FOR]` 唯一反事实读数（§3.19 原文）：`lbl=for_cond_6 fs=4 rs=4 lh=4 i=3 en=11 lfi=3 stop=1`，脚本 = **f124_container_orchestrator_pod_service_autoscale（冻结 PASSING）**。该读数里 `lfi` 已非空且 `lfi < loop_head_idx` ⇒ 停走成立。而 §4.7 的 ③ 模板谓词就是 `defer ∧ lfi ≠ null ∧ (lfi < loop_head_idx or lfi < range_start)` —— 它**不排除这一几何**：f124 的 `lfi=3` 与改动一无关，它必然来自**既有**记录器 —— 全文件非空写入点实测恰五枚：`:12814`（foreach 无条件记 `ei`）、`:12972`（foreach 一跳记 `ni`）、`:14925`（for 直接位置支）、`:14963`（for `in_cond_br_branch` 支）、`:16551`（while 侧），同帧更早的任一派发亦可留下该值 ⇒ provenance **不确定**。而 N1 的排除**不依赖 provenance**（见下表注）。⇒ 若按现稿落地，停走会在 f124 真触发，**该批必挂在自家硬零漂移门上**（`diff=0`），代价是一整个十二腿编译窗口。

**收窄的两种口径（均为待裁决，非本轮动作）**：

| 方案 | 谓词 | f124 | 形 9 | 代价 / 依据 |
|---|---|---|---|---|
| N1 `lfi ≠ 派发返回值` | 停走前加 `lfi != i` | 同一条实读给出 `lfi=3` 与返回值 `i=3` ⇒ **挡掉**；该等式由读数本身成立，与哪枚写入点无关 ⇒ 排除不依赖 provenance | 改动一记 `lfi=hop=3`，而通用路径返回 `exit_idx+1=7` ⇒ **放行** | 不改任何字段语义；须给 helper 增一枚 `dispatch_return` 入参 |
| N2 仅新记录器可停 | 改动一置一枚专用新鲜度标记，停走只认该标记 | 挡掉 | 放行 | 需新增 `self` 字段（非 `defer`，不触坑 5），改动面更大 |

**N1 不会挡掉本候选想放行的停走（构造论证，单向即足）**：改动一**不 return**（§4.7 明定「返回值不改」），故凡由它记录的事件，行走侧看到的返回值必为通用路径的 `exit_idx + 1`，而 `lfi = hop_idx < cond_idx ≤ exit_idx < exit_idx + 1` ⇒ 两值**恒不等** ⇒ 放行集 ⊆ N1 的通过集，N1 不可能削掉本候选要放行的任何事件。作为对照，直接位置两支（`:14925` 与 `:14963`）各自 `return exit_idx`（`:14935`/`:14971`）恰等于其写入的 `lfi` ⇒ 这类几何在 N1 下**必被排除**，f124 的实测读数正落在这一侧。⇒ 两集不相交的结论只用到「改动一不 return」这一条已实测口径，不依赖对 f124 provenance 的判定。

两案都要求 foreach 侧 `:7471–:7477` 的现行规则**逐字不改**（它在 6 个语料脚本上是活的，`[R14-FE]` 实测 10 条 `stop=1`，f124 亦在其中）⇒ 共用 helper 必须把「是否要求新鲜」参数化，foreach 传旧口径。
**收窄后的语料面**：包含集 ⊆ R14 实测的反事实集 `{f124}` 减去其自身排除 ⇒ **0**，形 9 由 §3.20 的 `hop=3 < ci=4` 与通用路径返回值 7 构造性放行。此为「一实测读数 + 两条构造」的派生，不是新读数；仍按流程规约 (a) 以落地批的 `DRIFT_DONE diff=0` 复验。

**3.22.4 顺带发现：`@NNNN` 形锚点不在 #74 卫生批覆盖面内**

#74 批按 `:NNNN` 形制清理失效行号，`@NNNN` 形制**从未进入其 grep**。全文件此类锚点共 **3 处**，本轮逐处实读：`:289` 与 `:12979` 引 `@7026` ⇒ 现文 `:7026` = `if (rhs_block.terminator) \|rhs_term\| {`，正是其所述「跟随 br 到 merge 块 / 消解 merge PHI」处理器的**首行** ⇒ **两处有效**；`:7468` 引 `@7702` 述「then 臂 `.br`→循环头派发置位」⇒ 现文 `:7702` 落在 `t_real_merge_idx` 反查块内，真实置位点为 **`:7841`**（`if (nested_else_idx != null) self.defer_loop_fallthrough = true;`，save `:7840` / restore `:7849`）⇒ **偏移 139 行，已失效**。本轮**未改源码**（注释亦属源码改动，须点头）；登记为 #74 未提交批的候选追加行（发射中性，1 行注释）。

**3.22.5 `ttag` 语料面能否零插桩回收（R17 前置的替代路径）= 不能**

留存物普查（实测）：`find . -name "*.log"`（排除 `.git`/`.zig-cache`）命中 **0**；全仓 `ttag` 出现 29 次，仅落在本工单与其配套变更文档两处 ⇒ R8.1 的 `/tmp` 原始日志确已按产物规约删除，`S09N` 语料 24 事件的 `ttag` 分布**不可回收**。⇒ **R17 的窄探针轮（#84）仍是唯一路径**，且其开轮前置已由 §3.21.2 清完。

**本轮（§3.22，任务 #86）零源码改动自证（2026-10-06 实测）**：`md5` = `fbe6382a2e0904b6740d771b88c409c7`、`wc -l` = 32797、`git diff --numstat` = `5 4`（#74 原样）、`grep -cE 'R1[4-8]|S09|armFallthroughStop' src/aot/native_linker.zig` = **0**（helper 名未被占用，且无插桩残留）、`git status --porcelain | grep -c '^ D'` = 0 ⇒ 代次未迁移，不产生新的九形门或漂移门读数。变更摘要：`docs/changes/2026-10-06/落地批锚点复验与f124阻断项_CODEGEN-006_322轮_2026-10-06_fbe6382a.md`（与 R16 文档同代次配套）。

## 4. 机制口径（R1+R2 取证 + R4/R5 实测；四类后果 = 四处缺失派发）

**先纠正**：本族**不经 `generateIfFromLabels`**（R1 九形 0 命中），全部在 `generateLabelDrivenBlockRange`（:7223）的**行内 `.cond_br` 处理器**（:8357 起）内完成；下列锚点为还原后的干净树 `native_linker.zig`（工作区 blob `3ae7b34e`，32546 行），行动前须 re-grep。**锚点代次补记（代次链，2026-10-04）**：`3ae7b34e`/32546 行（RC-5 批，影子轮读数锚点，本表与 §3.x 的行号一律属此代次、不改写）→ `22a217f0`/32607 行（A 批 +65/−4）→ `9490bf9f`/32663 行（D 批，累计 vs HEAD `+251/−29`）→ **`0e38b018b24b9ba0aa358f8d26a7f012`/32796 行（R9-B 批：IPD 结构 merge，本节 +134/−1，累计 vs HEAD `+385/−30`，2026-10-05 实测）**。行号映射规则（R9-B 代次实测，见 §4.5）：helper `findChainMergeByPostDom` 插在 `:1080` ⇒ **B 站点（`:10189`）之前的锚点一律 +117，之后的锚点 +133**（B 站点内联块自身 +16）。逐条定位请按符号 re-grep（`break :chain_unwind`、`ooo_arm_has_br = true`、`cs18_end`、`blk_p9`）；D 批代次的实测行号已写在 §3.8.1（R7 站点表）与 §7 D 行（落地记录）。

| 类 | 症状 | 缺失派发的确切站点（实测命中） | 同函数内已有的正确模板 |
|---|---|---|---|
| **A** | 末臂整块丢失（1/5/6） | 乱序 elseif 分支（`// Out-of-order` :9979）里臂尾 `.br` **只按边物化 PHI**：else 臂尾 :10052–:10053、then 臂尾 :10012–:10013；then 侧孪生分支同缺 :9099–:9100；~~三级链的 `chain_unwind`（:9111 / :10064）亦无臂尾循环派发~~ ⇒ **R5 实测否证（§3.6.4）**：`chain_unwind` 的守卫式臂尾站点（:9160 / :10113）在 96 脚本上 **0 事件**，形 8 实为该循环非守卫分支的裸 break ⇒ 另立 **D** 类 | 同一处理器的 else 臂终止符 switch（:9659 起，`.br` 分支 :9661）已实现**三段判据顺序**：① `is_back_edge`（目标 == `current_loop_cond_block`，或目标自身 `br` 回 cond 块 = 增量块）⇒ 消解 PHI + `continue :label`；② 否则目标标签命中 `for_cond_`/`while_cond_`/`foreach_cond_`/`do_while_body_`，或 `if_then_`+其后有 `if_merge_`、`ternary_then_`+`ternary_merge_`、`coalesce_rhs_`+`coalesce_merge_` ⇒ 保存/恢复 `return_generated`、`break_generated` 后 `generateLabelDrivenBlockRange(blk_i, end_idx, ...)`（:9704–:9721）；③ 否则 `merge_bi = blk_i`（:9723）。**修复照抄 ②**（另需 `defer_loop_fallthrough` 存/复，同 :8649–:8652） |
| **B** | 臂间互斥性丧失 / 串臂（4/7） | `nested_merge_idx` 求解（:9758–:9798，含 `blk0b` 兜底）把 **then 臂尾 `br` 进的循环头**当作链 merge（形 4/7 读得 `nmi=for_cond_7`）⇒ 走有序分支 :9965–:9977，`cs18_end` 兜底为 `end_idx` ⇒ 以 `[nti, end_idx)` 线性吞掉**兄弟 else 臂块**，双臂退化为顺序代码。**R5 实测修正（§3.6.2）**：机制到行成立，但站点判据 `else ∈ [nti,cs18_end) && !processed` 语料命中 20 脚本、收紧为「帧内未 processed 臂块」仍命中 2 个通过脚本 ⇒ 可落地谓词需**臂归属**（沿本 cond_br 的 else 目标可达）而非结构口径。**R6 再否证（§3.7.2/§3.7.4）**：把口径换成指针归属后，命中面为「C2 站点 7 事件 = 红 2（形 4/7）+ 绿 5（f025/f043/f067/f072/f080）」，`cs18_end==end_idx`、`nmi` 在帧内、`nce`、`hits` 四个字段无一能二分 ⇒ **臂归属判据也不可用**，B 的阻塞物改为「臂重联判据」（§3.7.3） | 乱序分支 :9979+ 的「then 内联 + `} else {` + else 内联」双臂形态 |
| **C** | 三臂顺序全执行（9） | ~~then 臂帧上界取 `end_idx`（`then_end` 计算 :8630–:8647 的 `break :blk end_idx` 兜底）⇒ 循环发射后同帧继续吞排在 merge 之后的兄弟臂块~~ **原「以 `else_bi` 为界」口径已被 R5 否证（§3.6.3：`[S06M] inh` 11 事件全 0）**；实测形状 = 帧 `[blk_i, then_end)` 内吞掉**内层链**的兄弟臂块（形 9 `sib=2 first=if_then_8`），而同口径在 4 个通过语料脚本上是「循环体内合法嵌套 if」⇒ 与 B 共用**臂归属判据**这一未闭合前置。**R6 再否证（§3.7.2）**：C1 站点归属口径命中「红 1（形 9 `hits=2`）+ 绿 4（f095/f124/`ref002_r1b` ×2，皆 `hits=1`）」，且 C3（40 读数）与 CD（1 读数）**零命中** ⇒ 形 9 的越界不在 else 臂派发帧也不在 `chain_unwind` 帧，区间侧无可判别谓词，阻塞物同样改为「臂重联判据」（§3.7.3） | `:9811–:9813`（`arm_hi` 截断）与 `:17003` 系 GIFL 的 `search_end` 取 `else_idx` 的界法 |
| **D**（R5 新立，替代原「形 8 归 A」口径） | 末臂整块丢失（8，三级链） | `chain_unwind`（:9111 / :10064）非守卫分支的**裸 break** `if (!else_is_back_edge) break :chain_unwind;`（:9143 / :10096）：三级链第二级的 else 目标是「带指令、尾 `br` 到链 merge」的**真实臂**（形 8 `els=if_else_7 elsterm=br`），既非守卫形态又非回边（顶层体 `clcb=null`）⇒ 连同臂体与末 else 臂（含 for）整体丢弃。**实测面 = 语料 0**（`[S06K]` 仅 f067 + 形 8，f067 走 `be=1` 的 `[S06N]` 出口；`[S06G]/[S06P]/[S06Q]` 全 96 脚本 0 事件） | 同一 `chain_unwind` 的守卫式分支（`try writer.print("if (")` + `generateInstructionSimple(ct_blk.instructions)` + else 目标 PHI 消解，:9160 / :10113 区）与 :8569–:8578 的窄四前缀派发集合 |
| **共因** | A/B/C 共同的放大器 | 链共享 `if_merge_`（含函数尾 `ret`）块号**排在臂块之前**，`:10423` 的 merge 续延在处理器层内联发 `ret` ⇒ `return_generated` 冒泡 → 行走头部不可达检查 :7241 把排在后面的 sibling 臂/循环块整体 `markReachableRestBlocks` 吞标 | `f124(修复13) 共享 merge return 外置 + else 链复活` :8691（then 侧已有复活机制，本单缺 else/elseif 侧同款） |

**§3.10 重定性（2026-10-04 生成码侧实测，必须与本表同读）**：本表的「四类后果 = 四处缺失派发」框架对 **A（1/5/6）与 D（8）成立** —— 那两类臂体在生成码里**确实不存在**；但 **B（4/7）与 C（9）两行的症状文字要改读**：生成码里三条臂的臂体**一块不少**，缺的是**链第二级 `cond_br` 的终止符派发**（连 `if (` 都没有、条件寄存器无消费者）⇒ 症状是 **臂守卫坍缩 + 兄弟臂按块序线性摊平**，不是「臂丢失」。两行里关于「区间上界 / `nested_merge_idx` / 帧上界」的归因，属 R1–R7 在派发帧区间侧的推断，已被 §3.9.3 三连否证限定为**不可用作落地判据**；落地判据改由 R8 在**内联发射器的 terminator 分派**上取证（见 §5 门 4）。

**⚠ 本段的「三条臂的臂体一块不少」在形 7 上已被后续实测推翻（2026-10-05 R16，§3.21）**：形 7 当前代次生成码实测为**二级守卫缺失 + 末臂（`if_else_4` 连体带 `for` 四块）整体未发射**，且其 IR **无任何 `if_merge_` 块**（13 枚探针里唯一）⇒ 形 7 属 **A/D 类（缺失派发）+ 缺守卫**的双缺陷，不受本段「非臂丢失」结论覆盖；形 4/9 仍按本段读数为准。

⇒ **修复的最小面 = A 类四处臂尾 `.br` 补循环头派发**（覆盖 1/5/6 三形；形 8 由 D 类覆盖，见 §3.6.4），不触碰 4/7/9 的区间判定。B、C 涉及 `.cond_br` 双臂语义，**前置影子实测已跑完三轮（§3.5/§3.6/§3.7，规约 (a) 满足）**，实测风险面为：改 `nested_merge_idx` 本身 ⇒ 命中 **8 个已冻结通过语料脚本**（3.5.3，非判别读数，不可直接落地）；~~改「区间上界以兄弟臂为界」⇒ 语料 0 命中，可落地~~ ⇒ **R5 否证**（收紧为 `sib` 口径后仍命中 f044/f080/f095/f102/f124/f177，§3.6.2/§3.6.3）⇒ **R6 再否证**（换成指针归属口径，命中面仍含 5 个通过脚本，§3.7.2）⇒ 区间侧（上界/归属）已无候选判据，B/C 的开放前置改为**臂重联判据**（§3.7.3）。

### 4.1 A 类修复实现蓝图（**设计稿，未落地、未提交**；§7 点头前不动源码）

四处臂尾站点若各写一份派发逻辑即为四重复制（违 DRY），故按 RC-5 既有惯例（共用谓词 `isOuterLoopLatch` :951、`findExitEdgeSourceIdx` :959 都落在 :937–:990 helper 区）**新增一个 helper，四处调用**：

```zig
// 返回 true = 已按循环头派发，调用方不得再 materializeEdgePhi；
// 返回 false = 维持原状（merge/回边/非循环头），由调用方按边物化 PHI。
fn dispatchArmTailBrIntoLoop(
    self: *Self,
    writer: anytype,
    func: *const IR.Function,
    target: *IR.BasicBlock,        // 臂尾 .br 的目标块
    end_idx: usize,
    cleanup_regs: []const usize,
    processed: *std.AutoHashMap(usize, void),
    loop_label_counter: *u32,
    indent: []const u8,
) anyerror!bool
```

判据**顺序结构**照抄模板（①回边 ⇒ ②派发 ⇒ ③merge），**谓词按 §3.5.2 实测口径收窄**（不得把模板 ② 的集合整段搬来当"照抄"，其中三条例外形态无实测支撑）：

1. 解析目标块号（指针等值线性扫描，与 :9662–:9671 同法）；
2. **回边与 latch 不改**（§3.5.2 实测：语料 5 事件的 `foreach_increment_*` 全在此类）：`target == self.current_loop_cond_block`，或目标自身 `.br` 回到 cond 块（增量块）⇒ `return false`（现行为已由 RC-4/RC-5 收口，本单禁止再动）；
3. **非窄循环头不改**：目标标签**不**命中 `for_cond_`/`while_cond_`/`foreach_cond_`/`do_while_body_` ⇒ `return false`。**禁止用 `isLoopHeadLabel`（宽集，10 前缀，含 `foreach_increment_`/`for_body_`/`for_loop_`）** —— 影子实测证其命中 f044/f067/f160 三个通过脚本。模板 ② 的三条例外形态（`if_then_`+其后有 `if_merge_`、`ternary_then_`+`ternary_merge_`、`coalesce_rhs_`+`coalesce_merge_`，:9707–:9713）在 88 脚本四处站点上**读数为 0** ⇒ 本轮不纳入 helper（规约 (a)：未实测即不写），若后续语料出现该类目标再另开影子轮。
4. 命中 ⇒ 保存并置 `defer_loop_fallthrough = true`（同 :8649–:8652）、保存/清零 `return_generated`、`break_generated`（同 :9715–:9721）后 `generateLabelDrivenBlockRange(target_idx, end_idx, ...)`；
5. 回来后按 :8657–:8670 的 `lfi_is_join` 口径把**乱序共享 merge 交还外层**，再按需恢复三标志 ⇒ `return true`。

调用方四处（:9056 / :9097 / :10010 / :10050，`ooo_arm_has_br = true;` 保留在调用之前）统一改为 `if (!try self.dispatchArmTailBrIntoLoop(...)) try self.materializeEdgePhi(...)`。

| 风险 | 说明 | 处置口径 |
|---|---|---|
| R-1 ~~二次吞臂（形 9）~~ → **实测否证** | 影子轮证：形 9 在四处臂尾站点**零 `[S06A]` 读数** ⇒ A 的派发不被该几何触达，A 不会改变形 9（§3.5.5 第 3 条） | 残余风险改记为：**A 修不掉形 8**（形 8 臂尾窄集读数为 0，其三级链落 `chain_unwind`，属第五类站点，本轮未插桩）⇒ A 落地后本单门预期 `same` 由 2 升至 **5**（1/5/6 转绿），不是 6 |
| R-2 标记权 | 禁止 `processed.remove` 非本帧拥有的块（RC-5 facet-2 实测：卸载共享增量 ⇒ 重发） | helper 只写 `generateLabelDrivenBlockRange` 自身的标记路径，不卸载任何既有标记 |
| R-3 递归深度 | 臂内联上下文再嵌一帧行走，属 CODEGEN-004（大函数 sibling 块栈溢出）族 | 复测门 A 17 形 + 官方 68 回归，并对最大语料脚本比对 `main.zig` 行数 |

**预期形状映射（§3.5 实测口径）**：A ⇒ **1/5/6 转绿**（三形在 :10089 站点有窄集 `lh=1` 读数；另 `perf001_hotspot_probe_tmp` 同站点命中，可作第四正对照）；**8 不覆盖**（臂尾窄集读数 0，三级链落 `chain_unwind` = 第五类站点，未插桩）；4/9 需 §3.5.4 的「区间以兄弟臂为界」口径（语料 0 命中）；7 **口径未闭合**（五类探针均无独有读数，需 R5 细探针）。⇒ 单落 A 的本单门预期为 `same=5 differs=4`，不得按 `same=6` 验收。

### 4.2 A 批落地记录（**实测，2026-10-04；已落地工作区，未暂存、未提交**）

代次校验：`native_linker.zig` md5 `d0b6dde9156fa8c34aae23826542bbb3`、**32607 行**（相对 RC-5 干净树 32546 行 +61），`git diff --stat` = **+65 / −4**（一个 helper + 四处调用点，无其它改动）。`runtime_lib_template.zig` 未触碰。

**落地形态（与 §4.1 蓝图逐条对应）**：

| 蓝图条目 | 实测落地 | 站点（落地后代次行号，行动前已 re-grep） |
|---|---|---|
| helper 一处 | `fn dispatchArmTailBrIntoLoop(...)` 新增，返回 `anyerror!bool` | `:991`（紧随 `findExitEdgeSourceIdx` 之后、`writeBrInLoopContext` 之前，与 RC-5 既有 helper 同区） |
| 谓词①块号解析 | `self.tryFindBlockIndex(func, target) orelse return false` | 用 `tryFindBlockIndex` 而非 `findBlockIndex`（后者未命中即 `std.debug.panic`） |
| 谓词②回边/latch 不改 | `ti == current_loop_cond_block` **或** 目标自身 `.br` 回 cond 块 ⇒ `return false` | 与 §3.5.2 实测口径字面一致 |
| 谓词③窄四前缀 | 逐条 `startsWith`：`for_cond_`/`while_cond_`/`foreach_cond_`/`do_while_body_` | **未用** `isLoopHeadLabel`（宽集命中 f044/f067/f160）；模板 ② 的 `if_then_+if_merge_`/`ternary_then_+ternary_merge_`/`coalesce_rhs_+coalesce_merge_` 三条例外形态 114 脚本读数 0 ⇒ 按规约 (a) **未写入** |
| ④派发 | 存/清 `return_generated`、`break_generated` 后 `generateLabelDrivenBlockRange(ti, end_idx, …)` | 照抄模板 ②（`:9704–:9721` 段） |
| ⑤交还 merge | **未落地**：模板 ② 本身不设 `defer_loop_fallthrough`，而 §4.1 第 5 条要求的 `lfi_is_join` 交还路径**未在影子轮中被读为必要**；`defer` 设置面属 RC-5「禁止加宽」约束 ⇒ 本轮按实测口径最小写，不引入未实测的交还 | — |
| 调用方四处 | 统一 `if (!try self.dispatchArmTailBrIntoLoop(…)) try self.materializeEdgePhi(…)`，`ooo_arm_has_br = true;` 保留在调用之前 | `:9106`（then 臂 `br_t0`）、`:9151`（else 臂 `br_t`）、`:10068`（then 孪生 `br_t0b`）、`:10112`（else 孪生 `br_t`） |

**验收门实测（串行跑，批内无并发编译）**：

| 门 | 读数 | 判据 |
|---|---|---|
| 本单 9 形门 | `C006_TL_GATE_DONE total=9 same=5 differs=4` | **精确命中 §4.1 预测**：1/5/6 转绿，2/3 原绿形未劣化，红点为 4/7/8/9 |
| 门 A 17 形等值 | `PROBE_DONE total=17 same=17 differs=0` | 不劣化 |
| RC-4 门 | `RC4_PROBE_DONE total=4 same=3 differs=1` | 唯一红点仍为 `ref003_crash_attr_tmp`（归 REF-003），非本批劣化 |
| RC-5 八形合串 | `IDENTICAL` | 不劣化 |
| do-while 门 | `DOWHILE_PROBE_DONE total=2 same=2 differs=0` | 不劣化 |
| **冻结漂移（硬零门）** | `DRIFT_DONE total=68 ok=68 diff=0 notemp=0 norow=0` | **`diff=0` 达成** ⇒ 语料逐字节零漂移，与 R4「语料命中面 0」的预测一致 |
| 官方 68 回归 | `TOTAL 68 / PASS 67 / SKIP 1 / FAIL_COMPILE 0 / FAIL_RUNTIME 0 / FAIL_DIFF 0` | SKIP 项为 `f004_oop_deep_inheritance_magic.php`（`PHP_error_exit=255`，PHP 自身即失败的既有排除项，非本批新增） |
| 抽查 5 脚本 md5 | `SPOT_DONE ok=5 bad=0` | 与冻结基线逐行等值 |
| 确定性巡检 | `SWEEP_DONE total=68 mismatch=0 notemp=0` | 每脚本两跑 `main.zig` md5 全等 |
| `zig build test --summary all` | `21/21 steps succeeded; 326/326 tests passed`，`rc=0` | 全绿（末尾 `failed command:` 行为该命令的既有幻影行，判据取 summary + rc） |
| `zig build` | `rc=0` | 编译通过 |

**耗时实测**：探针五门串行约 6 分钟；全量漂移 68 脚本约 16 分钟；官方回归 + 抽查 + 确定性巡检（68×2 跑）合计约 42 分钟；`zig build test` 命中缓存约 1 分钟。

**连带收益（PERF-001 §6 的到期复测）**：`perf001_hotspot_probe_tmp` mode=1 由「臂未执行 ⇒ 0.42s 空跑」变为**执行且与 PHP 逐字节等值**（`M1 g=449999985000000 h=90000000`），AOT 侧 6.57s vs mode=2（函数内局部同构循环）1.59s ⇒ **H1 全局按名寻址净成本 ≈ 166 ns/迭代**。详见 AOT-PERF-001 §3.1。

**尚未达成的门**：本单终态 `same=9` 仍需 4/7/8/9 四形 ⇒ 形 8 属 **D 批**（站点/谓词已实测、语料面 0，但**正确发射形态未实测**：`chain_unwind` 非守卫分支的裸 break 若改为「按臂派发」，需先取证该帧应发 `} else {` 还是内联续帧，R5 只证到「该站点是缺失派发点」，未证到目标形态 ⇒ 本轮未动，见 §7）；形 4/7/9 需 **R7 臂重联判据**（§3.7.3）。

### 4.3 D 批落地记录（**实测，2026-10-04；已落地工作区，未暂存、未提交**）

代次校验：`native_linker.zig` md5 `fdeebc14daa456bb94437345ab771697`、**32663 行**（相对 A 批 32607 行 +56），D 批本体 `git diff` = **+58 / −2**，累计 vs HEAD `0ff09cf` = **+251 / −29**（RC-5 `128/23` + A `65/4` + D `58/2`），工作 blob `9490bf9f`。`runtime_lib_template.zig` 未触碰（md5 `008b7b639f1069cb73e443064e115ed1` 不变）。

**落地形态（谓词字面 = R5 实测口径，未加宽）**：

| 条目 | 实测落地 | 站点（落地后代次行号，行动前已 re-grep） |
|---|---|---|
| helper 一处（DRY） | `fn emitChainUnwindArmPair(...) anyerror!bool` 新增，取 `cond: IR.Register`（`{id: u32, type_: Type}` 纯值、无所有权 ⇒ 按值传参安全）+ `else_block` 指针 | `:1035–:1072`（紧随 A 批 `dispatchArmTailBrIntoLoop`，与 RC-5 helper 同区） |
| 触发门（不改） | 仅在既有 `!guard_form` 且 `!else_is_back_edge` 分支进入 | 孪生两处 `:9245` / `:10211`，**替代原裸 `break :chain_unwind;`** |
| 形态守卫三道（收窄，非加宽） | `tryFindBlockIndex(else_block) orelse return false`；`ei <= then_idx ⇒ return false`（乱序）；`processed.contains(ei) ⇒ return false` ⇒ 任一不成立即**维持原 break（不发射）** | helper 首三行；`tryFindBlockIndex` 而非 `findBlockIndex`（后者未命中 panic） |
| then 臂区间 | `generateLabelDrivenBlockRange(cti, **ei**, …)` ⇒ **以兄弟 else 臂为上界**，避免同帧线性吞并兄弟臂（与 C 类同因） | 形 8 实测 `[6,7)` ⇒ 只物化 `if_then_6` |
| else 臂区间 | `generateLabelDrivenBlockRange(ei, **end_idx**, …)` ⇒ 由区间行走正常派发臂内循环/退出块（形 8 为 `for_cond_10`/`for_body_11`/`for_exit_13`） | 未自造循环派发，复用区间行走 |
| 标志存/复 | `return_generated`/`break_generated` 于两臂后**无条件恢复**（两臂臂尾各回落链共享 merge ⇒ if/else 之后恒可达） | 与同函数单臂出口 `:9202–:9209` 同款口径 |
| `defer_loop_fallthrough` | **未引入**：与 A 批同判——模板 `:9704–:9721` 段本身不设该位，影子轮亦未把它读为必要；且 `defer` 设置面属 RC-5「禁止加宽」硬约束 | — |

**为什么是「区间派发」而不是内联**：同函数已有双臂内联模板（`:9062–:9164`：逐条 `generateInstructionSimple` + 终止符 switch）。把它移植到 `chain_unwind` 需在**两个孪生站点**各写约 100 行（then/else × 指令 + `.ret/.throw/.br/.cond_br` 四态），属重复实现；区间派发用 38 行 helper 取得同一效果，且臂内循环由既有区间行走负责。

**验收门实测（全部串行，批内零并发编译）**：

| 门 | 读数 | 判据 |
|---|---|---|
| 本单 9 形门 | `C006_TL_GATE_DONE total=9 same=6 differs=3` | **精确命中 §5 门 4 的 A+D 批预测终态**：形 8 转绿，1/2/3/5/6 未劣化，红点缩到 4/7/9 |
| **新立 D 门（双臂取臂面）** | `C006_D_GATE_DONE total=2 same=2 differs=0` | D-1 取末节点 then 臂 ⇒ 真值 `T10 b4` 单行，**否证「then 臂落入 else 臂体」fallthrough**；D-2 取链首臂 ⇒ `T11 b2`，否证首臂串跑 |
| 门 A 17 形等值 | `PROBE_DONE total=17 same=17 differs=0` | 不劣化 |
| RC-4 门 | `RC4_PROBE_DONE total=4 same=3 differs=1` | 唯一红点仍 `ref003_crash_attr_tmp`（`rc=139`，归 REF-003） |
| RC-5 八形合串 + F-B/F-H 单形 | `IDENTICAL` + 两形 `IDENTICAL` | facet-1/facet-2 未回退 |
| do-while 门 | `DOWHILE_PROBE_DONE total=2 same=2 differs=0` | 不劣化 |
| **冻结漂移（硬零门）** | `DRIFT_DONE total=68 ok=68 diff=0 notemp=0 norow=0` | **`diff=0` 达成** ⇒ 基线**不需重冻结**，与 R5「`[S06R] be=0` 语料命中面 0」的预测一致 |
| 官方 68 回归 | `TOTAL 68 / PASS 67 / FAIL_COMPILE 0 / FAIL_RUNTIME 0 / FAIL_DIFF 0 / SKIP 1` | SKIP 仍为 `f004_oop_deep_inheritance_magic.php`（`PHP_error_exit=255`，既有排除项） |
| 确定性巡检 | `SWEEP_DONE total=68 mismatch=0 notemp=0` | 每脚本两跑 `main.zig` md5 全等 |
| 抽查 5 脚本 md5 | `SPOT_DONE ok=5 bad=0` | 与冻结基线逐行等值 |
| `zig build test --summary all` | `21/21 steps succeeded; 326/326 tests passed`，`rc=0` | 全绿（判据取 summary + rc，末尾 `failed command:` 为既有幻影行） |
| `zig build` | `rc=0`，墙钟 70s（19:11:28→19:12:38） | 编译通过 |

**耗时实测**：D 批门串（本单 9 形 + 探针五门 + D 门）约 6 分钟；漂移 68 脚本 **13m17s**（19:16:51→19:30:08）；官方 68 回归 **16m02s**（19:30:47→19:46:49）；确定性巡检 **25m41s**（19:47:10→20:12:51）；抽查 1m01s；`zig build test` 命中缓存 5s。

**自我否证 / 未声称项（写进口径）**：

1. **未声称解决 C 类区间问题**。else 臂沿用外层 `end_idx` 作上界，理论上仍可吞并排在链 merge 之后的 sibling 块（与形 9 同因）。形 8 与全语料 68 脚本实测**未出现**该几何（`diff=0` + `same=6`），故本批按实测口径落地，**不预加**未实测的区间收窄判据。
2. **未引入 `defer_loop_fallthrough`、未动 `processed.remove`**（RC-5 两条硬约束：设置面禁止加宽；非本轮消费的块禁止卸载标记）。
3. 本批只覆盖**三级链末节点取双臂**这一条形态；形 4/7/9 一条未动，仍为红（预期）。

**尚未达成的门**：本单终态 `same=9` 只剩 **4 / 7 / 9** 三形，全部属 B/C 类，前置为 **R7 臂重联判据**（探针口径已写成可执行设计稿，见 §3.8；任务 #60）。

### 4.4 锚点代次定位表（**实测，2026-10-04 收尾轮；只读复核，零代码改动**）

本单 §3.5–§3.7 的取证记录混用了**两代**行号：R1/R2/R4 轮写在 RC-5 代次（blob `3ae7b34e`，32546 行），A/D 站点写在 `22a217f0` / `9490bf9f`。按流程规约 (b)，**旧数字一律视为历史读数**；下表把前者逐条换算到当前工作区树（blob `9490bf9f`，32663 行，md5 `fdeebc14daa456bb94437345ab771697`），每条均由**符号 / 字面量 grep 实测**得到，非按偏移推算。

| §3.5–§3.7 引用的旧锚 | 语义 | 当前树实测 | 实测依据 |
|---|---|---|---|
| `:8357` | 主 `.cond_br` 处理器（本单 ownership 结论的落点） | **`:8448`** `.cond_br => {` | `fn generateLabelDrivenBlockRange` = `:7314`；从 `:7314` 到 `:8600` 之间 `.cond_br` 分支**唯一**命中 |
| `:7209` / `:7223` / `:7241` | mark-rest 扫描与可达性判据 | **`:7332`**（`if (self.return_generated or self.break_generated)`）→ **`:7335`**（`try self.markReachableRestBlocks(...)`）→ **`:7336`**（`return;`）；helper 定义 **`:25471`** | `grep -n markReachableRestBlocks` = 7335 / 25471 两处命中 |
| `:9099–:9100` | then 侧孪生「臂尾只物化 PHI、不派发循环头」 | **`:9152`**（A 批 `dispatchArmTailBrIntoLoop`）+ **`:9153`**（`materializeEdgePhi`） | `grep -n dispatchArmTailBrIntoLoop` = 991 / **9152 / 9197 / 10119 / 10163** |
| `:10012–:10013` | 同上第二孪生 | **`:10119`** + **`:10120`** | 同上；`materializeEdgePhi` = 9153 / 9198 / 10120 / 10164 |
| `:10052–:10053` | 同上第三孪生 | **`:10163`** + **`:10164`** | 同上 |
| `:9111` / `:10064` | `chain_unwind`（D 类站点所在） | 两处 `chain_unwind: while (true)` = **`:9210`** / **`:10176`**；裸 `break :chain_unwind` = **`:9246`/`:9262`** 与 **`:10212`/`:10228`**；D 站点 = **`:9245`** / **`:10211`**（helper 定义 `:1035`） | `grep -n chain_unwind`、`grep -n emitChainUnwindArmPair` |
| `:9704–:9720` | else 臂的「循环头派发模板」（**`target_is_loop_header` 只是描述性称呼，不是标识符**） | **`:9808–:9825`**：`else if (startsWith(target_label, "for_cond_") / "while_cond_" / "foreach_cond_" / ("if_then_" ∧ `findBlockByLabelPrefix`(…, `"if_merge_"`)) / ternary / coalesce / "do_while_body_")` ⇒ `saved_rg`+`saved_break` + `generateLabelDrivenBlockRange(blk_i, end_idx, …)` | `grep -n target_is_loop_header` 在本函数内**零命中**（全文件仅 1111/1116、12910/12915、14866/14871、17245/17250）⇒ 必须按字面量 `for_cond_` + `findBlockByLabelPrefix` 定位 |
| `:9758–:9798` | B 站点 `nested_merge_idx` 解析 | **`:9862`**（`var nested_merge_idx: ?usize = null;`）… **`:9884–:9901`**（`blk0b` 兜底）⇒ 区间 **`:9862–:9902`**；另一处读点 `:9550` | `grep -n nested_merge_idx` |
| `:10423` | 链共享 `if_merge_` 的延续内联（放大器） | **`:10540–:10548`**（`// 处理 merge 块` ⇒ `if (merge_bi) \|mi\|` ⇒ `if (mi >= end_idx)` 交还外层） | `sed -n '10536,10548p'` 逐行核对 |

**由本表得到的两条结论**：

1. **分段偏移表（`3ae7b34e` → `9490bf9f`，见 AOT-PERF-001 §8.1）在本单再获 6 处独立验证**：`8357+91=8448` ✓、`9704+104=9808` ✓、`9758+104=9862` ✓、`10012+108=10120` ✓、`10052+112=10164` ✓、`10423+117=10540` ✓；唯 `:9099–:9100` 落在插入 hunk 的**边界内**，映射出现 ±1～±2 偏差 ⇒ 属「hunk 内部行不成像」的预期误差，不是偏移表本身有误。
2. **§3.8 的十组站点行号已在本代次实测为精确值**（`:8737`/`:8742`、`:8676–:8694`、`:8695–:8764`、`:8698–:8711`、`:8720–:8737`、`:8748–:8760`、`:10069`、`:10081`、`:9521–:9533`），逐条符号核对通过 ⇒ **R7 影子轮（任务 #60）不再需要任何前置定位工作**，只等老铁点头即可插桩。

### 4.5 R9-B 代次锚点换算表（**实测，2026-10-05；符号 / 字面量 grep，非偏移推算**）

当前工作区树 = R9-B 落地后（blob `0e38b018b24b9ba0aa358f8d26a7f012`，32796 行，vs HEAD `+385/−30`，vs D 批 `+134/−1`）。§4.4 表中所有 `9490bf9f` 行号属**上一代次**，按本表换算：

| 语义 | `9490bf9f`（D 批） | 当前树实测（R9-B） | 实测依据 |
|---|---|---|---|
| IPD helper（**本批新增**） | — | **`:1080`** `fn findChainMergeByPostDom(self: *Self, func, node_idx) !?usize` | `grep -n fn.findChainMergeByPostDom` |
| B 站点选路（**本批新增**） | `:10063`（`if (nested_merge_idx) \|nmi\| {`） | **`:10189`** `const nmi: usize = blk_p9: {` ⇒ `:10192` 三条件门 ⇒ `:10195` `break :blk_p9 nmi_raw` | `grep -n blk_p9` |
| A 批 helper | `:991` | **`:991`**（未变，插在 IPD helper 之前） | `grep -n fn.dispatchArmTailBrIntoLoop` |
| D 批 helper | `:1035` | **`:1035`**（未变） | `grep -n fn.emitChainUnwindArmPair` |
| `fn generateLabelDrivenBlockRange` | `:7314` | **`:7431`**（+117） | `grep -n` |
| 主 `.cond_br` 处理器 | `:8448` | **`:8565`**（+117） | 从 `:7431` 起首个 `.cond_br => {` |
| mark-rest 扫描三件套 | `:7332/:7335/:7336` | **`:7449/:7452/:7453`**；helper 定义 `:25471` → **`:25604`**（+133，在 B 站点之后） | `grep -n "if (self.return_generated or self.break_generated)"` / `markReachableRestBlocks` |
| 臂尾派发四站点（A 批） | `:9152/:9197/:10119/:10163` | **`:9269/:9314/:10252/:10296`**（前两处 +117，后两处 +133） | `grep -n dispatchArmTailBrIntoLoop` |
| `chain_unwind` 循环头 / D 站点 | `:9210/:10176` / `:9245/:10211` | **`:9327`/`:10309`** | `grep -n "chain_unwind: while (true)"` |
| `nested_merge_idx` 声明（else 侧处理器） | `:9862` | **`:9979`**（+117）；then 侧另有一处 `:9013`，同样 +117 | `grep -n nested_merge_idx` |
| **五条件 merge 回传（路线 ③ 的 T1 站点，2026-10-05 新增实测）** | — | 消费入口 **`:8865`** `if (self.last_loop_fallthrough_idx) \|lfi\| {` ⇒ 条件式 **`:8871`**（`const lfi_is_join = (lfi < blk_i or …`）⇒ 判定 **`:8877`**（`if (lfi_is_join) {`，`:8878` 起 `merge_bi = lfi` + `processed.remove(lfi)`） | `grep -n lfi_is_join` = **全文件仅 8871/8877 两处**；`grep -n "last_loop_fallthrough_idx) \|lfi\|"` = 8865 唯一 |
| **T3 = `cs18_end` 线性分支（路线 ③ 的 T3 侧，2026-10-05 新增实测）** | — | 求解 **`:10202`**（`const cs18_end: usize = blk18: {`）⇒ 派发调用 **`:10214`**（`generateLabelDrivenBlockRange(writer, func, nti, cs18_end, …)`）；该调用之后**无 `lfi` 读取**（`10214` 之后下一处读点属另一函数族 `:11894`） | `grep -n cs18_end` = 10202/10214 两处 |
| else 臂「循环头派发模板」（A 批照抄源） | `:9808–:9825` | **`:9925–:9942`**（+117）⇒ 兜底 `merge_bi = blk_i;` **`:9943`** | `grep -n '"for_cond_"'` 在 9850–10000 区间唯一命中 9925 |
| 链共享 merge 的延续内联（放大器） | `:10540–:10548` | **`:10673`**（`// 处理 merge 块`）⇒ `if (merge_bi) \|mi\|` ⇒ **`:10681`**（`if (mi >= end_idx) {` 交还外层） | `grep -n "处理 merge 块"` / `grep -n "if (mi >= end_idx)"` |
| **函数级否决位（PERF-001 用，2026-10-05 新增实测）** | — | 声明 **`:17724–:17729`**（`has_do_while`/`has_switch`/`has_match`/`has_recursive_call`/`has_exception_handler`）⇒ 置位 **`:17732`** ⇒ AST-direct 门 **`:17771`**、调用 `tryGenerateFromLabels` **`:17775`** ⇒ 结构化门 **`:17816`**、调用 `tryGenerateStructuredControlFlowNew` **`:17825`** | `grep -n has_do_while` |
| **ReleaseFast 逃逸门（PERF-001 用，2026-10-05 新增实测）** | `:32195`（`3ae7b34e`）→ `:32312`（`9490bf9f`） | **`:32445`** `if (zig_code.len > 200_000 and self.config.optimize_level == .release_small)` | `grep -n 200_000`；默认档 `compiler.zig:140` 未变（`grep -n "optimize_level: OptimizeLevel"`） |

**映射规则**：helper 插入使 B 站点**之前**的锚点 +117，B 站点内联块使**之后**的锚点 +133 ⇒ 两处 `markReachableRestBlocks` 命中（`:7452` 调用点 / `:25604` 定义点）分别落在两侧，即该规则的直接验证。

**R9-B 增量构成（`diff` 对 D 批干净备份 `/tmp/nl_backup_9490bf9f_r8.zig` 实测，非估算）**：`1072a1073,1085` + `1073a1087,1190` ⇒ helper 区新增 **117 行**（`:1073`–`:1189`，含 6 行 doc 注释，`fn` 在 `:1080`）；`10063c10180,10196` ⇒ B 站点 **17 行替换 1 行**（`:10180`–`:10196`，含 4 行口径注释）⇒ 合计 `+134/−1`，行数 32663 → **32796**（净 +133）✓。

**B 站点判据最终口径（落地版，与 §3.14 同读）**：仅当 `nested_merge_idx` 存在 ∧ `nmi_raw >= nti` ∧ `M = IPD(ei)` 存在 ∧ `M ∈ [start_idx, end_idx)` ∧ `M < nti` 时，把 merge 改判为 `M`，从而交由下方既有的 `nmi < nti` **乱序双臂模板**发射；其余路径（乱序形态、共享 merge、`nmi == null`）逐字不改，且 IPD 只在 `nmi_raw >= nti` 时惰性求值 ⇒ 语料实测全量仅 24 次调用，四脚本编译秒数差在噪声内（§3.14 表）。链节点直接取 else 块索引 `ei`，不做指针扫描。

**未覆盖 / 未改动（本批刻意保留）**：① 同一函数内还有三处同形的 `if (nested_merge_idx) |nmi| {` 选路站点 —— 当前树 **`:9227`（then 侧，D 批 `:9110`）/ `:9667`（D 批 `:9550`）/ `:10622`（D 批 `:10489`）**，本批**均未插桩、均未改**（`grep -n "if (nested_merge_idx) |nmi| {"` = 7 处命中，其中 3 处属另一函数 `:17075/:17174/:17195`）⇒ 是否存在对称需求属未测，改动前须先出各自的影子读数；② `nmi == null` 的共享 merge 路径不接 IPD；③ `findChainMergeByPostDom` **无函数级缓存**（每次调用重建反向 CFG + 后序 DFS + CK 定点；实测 24 次调用可接受，但高链密度语料有退化风险）；④ 形 7（`IPD=null`）与形 9（C 站点判据语料面 5/10）不由本批改判。

### 4.6 锚点卫生批代次（**纯注释、无代码行；实测 2026-10-05**）

工作区树 = 提交 `497edc6` 之后、注释锚点卫生批落地：blob `fbe6382a2e0904b6740d771b88c409c7`、**32797 行**、vs `497edc6` `+5/−4` 且 `git diff -U0` 逐行核过**全部为注释行**。

改动对象是**注释里写死的行号**（全文件 `grep -nE '(^//|^\s+//).*:[0-9]{4,5}'` 实测只有这两个站点；改后剩余命中即本批自己写入的三行）：

| 站点 | 注释内旧引用（初写代次） | 本批重写为（`0e38b018`/32796 实测） |
|---|---|---|
| `markReachableRestBlocks` 的 doc 注释（闭包版否证依据） | 兜底 `:6497–:6514` / 判定 `:6505` / `return false` `:6513` / 顶层行走调用 `:6494` | `:6740–:6757` / 判定 `:6748` / `return false` `:6756` / 调用 `:6737` |
| `generateWhileFromLabels` 内 RC-3 注释（照抄源指引） | foreach 派发表 `:11516–:11525`、RC-2 判据 `:11556–:11573`；for 派发表 `:13694–:13703`、判据 `:13717–:13732` | foreach 派发表 `:11801–:11810`、RC-2 判据 `:11841–:11857`；for 派发表 `:13979–:13988`、判据 `:14002–:14016` |

**+1 换算规则（本批引入；读 §4.5 表时必用）**：RC-3 注释由 2 行改拆为 3 行 ⇒ **`:15621` 之后**的锚点相对 R9-B 代次**一律 +1**，之前不变。重测（grep 锚点符号，非推算）：不变侧 `fn generateLabelDrivenBlockRange` 仍 `:7431`、`blk_p9: {` 仍 `:10189`；+1 侧 `fn markReachableRestBlocks` `:25604` → **`:25605`**、函数级否决位声明 `:17724–:17729` → **`:17725–:17730`**（置位行 `:17732` → `:17733`）、ReleaseFast 逃逸门 `:32445` → **`:32446`**。⇒ §4.5 表体**不改写**（其行号属 `0e38b018` 代次，按 §4「锚点代次补记」纪律保留原值），本小节即其换算依据。

**发射中性（实测，非推断）**：`timeout 560 zig build` rc=0；全量冻结基线漂移门 `DRIFT_DONE total=68 ok=68 diff=0 notemp=0 norow=0`（68 个 `main.zig` 的行数 + md5 与冻结记录逐字相符 ⇒ 强于既往「五处抽查」口径）；本单九形门 `C006_TL_GATE_DONE total=9 same=7 differs=2`，红点仍 = 形 7 / 形 9，两条 `DIFF` 签名与 §3.17.2 登记值逐字相同。

### 4.7 形 9 候选设计稿：for 侧「exit 块一跳回落目标」记录 + for 分支帧内停走（**设计稿，未落地；待 §3.20 语料面读数与老铁点头**）

> ⛔ **落地前必读（2026-10-06 复验，§3.22）**：本节全部锚点与模板标识符在当前代次 `fbe6382a`/32797 **逐字等值**（§3.22.1 表），但**改动二按现稿谓词逐字落地会重触发 R14 已实测的 f124 停走反例 ⇒ 该批必挂在自家硬零漂移门上**（§3.22.3）。⇒ 「落地」点头的前置已改为**先裁决窄化口径 N1 / N2**；改动一本体不受影响。

**三条已实测读数如何拼成一条因果链**（行号属**干净代次** `fbe6382a`/32797，除注明者外）：

1. **形 9 的 IR 事实**（R15 单形预探针读数，插桩代次 32825 行）：`[R15-X] lbl=for_cond_4 ci=4 bi=5 li=5 ei=6 elbl=for_exit_7 en=9 defer=1 inb=1 tk=0 hop=3 hlbl=if_merge_2 hoplt=1 nlfi=0` ⇒ 出口块自身排在循环头**之后**（6 > 4），但它 `tk=0`（终止符是 `.br`）**一跳**落到 `if_merge_2`（3 < 4）。
2. **为什么没记录**：for 侧只有两处写 `lfi` —— `:14923` 的 `defer ∧ exit_idx < cond_idx`（**直接位置**测试，6 < 4 假）与 `:14961` 的「出口块标签是 `for_loop_`/`foreach_increment_`」+ `in_cond_br_branch`（`for_exit_` 不匹配）⇒ 两者皆不进，控制落到 `:15026 return exit_idx + 1 = 7`（R15 `[R15-RT] site=9` 实测同值），`lfi` 保持 `null`（R14 `[R14-FORX] nlfi=0` 独立复证）。对照 foreach 侧：`if (exit_idx) |ei| { self.last_loop_fallthrough_idx = ei; … }`（`:12812–:12814`）**有出口块就无条件记录**，且行走侧 `:7471–:7477` 有帧内停走 —— for/while 两侧同时缺这两件（while 侧记录条件见 `:16550`（判据行）⇒ `:16551`（写入行），同样只看直接位置/latch）。
3. **记录之后谁会接住**：`:8859` 递归行走返回后，`:8865–:8895` 的 `lfi_is_join` 五条件消费者**已存在且已验证对形 9 成立** —— R13 落地批实测读数 `[R13-FB] m=3 pos=1 np=3 isLH=0 iscb=0 iseb=0 pro=0 join=1`（候选块同为一跳目标 3）⇒ 一旦 `lfi` 非空，`merge_bi = lfi` / `processed.remove(lfi)` / 清 `return_generated` / 清 `break_generated` / 臂末 PHI 物化四句会照旧执行，无需新增消费者。

**先例（实测，同代次）**：一跳记录**不是新造机制** —— foreach 侧在 `exit_idx == null` 时已经这么干：`:12962–:12972` 从 cleanup 块的 `.br` 目标按指针反查得 `ni`，然后 `self.last_loop_fallthrough_idx = ni; self.last_loop_fallthrough_src_idx = cleanup_idx;`，并在 `:12981–:12982` 用 `self.defer_loop_fallthrough and ni < cond_idx` 抑制就地消费。⇒ 本候选 = 把「foreach 的 cleanup→.br 目标一跳记录」与「foreach 的帧内停走 `:7471–:7477`」两件**已验证**口径，补到 for 侧的 `exit 块→.br 目标` 同几何上。R13/R14 被否证是因为它们新造了静态谓词；本候选没有新谓词。

**改动一（记录侧，实测收窄为「纯记录支」）**：实文复核（`nl_r15_backup.zig` 干净代次）推翻了原稿「插在 `:14923` 之前替换直接位置支」的写法 —— 通用发射路径 `:14977–:15026` **本来就会** `processed.put(exit_idx)` + 逐条发射 `exit_block` 指令 + 处理其终止符，而 `.br` 分支 `:14996–:15021` 只在目标是循环头（`target_is_loop_header`，`:14999–:15003`）时才递归派发，落到 `if_merge_` 一类目标时**什么都不发**。⇒ 改动一只需**新增记录、完全不动发射/标记/返回值**：

- 位置：插在 `:14975`（`for_loop_`/`foreach_increment_` 支结束）之后、`:14977` `try processed.put(exit_idx, {});` 之前；`:14923`、`:14940`、`:14951` 三支**逐字不动**（三支各自提前 `return`，与新增支互斥，无需写成 `else`，原稿坑 2 自动消解）；
- 判据（窄口径，逐字对应 §3.20 实测的 `HOPQ` 面）：`self.defer_loop_fallthrough` ∧ `exit_block.terminator` 为 `.br` ∧ `hop_idx < cond_idx`（`hop_idx` = 按指针在 `func.blocks.items` 中匹配 `.br` 目标所得索引，找不到则不记录），其中 `hop_idx` 计算口径复制 `:15005–:15010` 的既有指针匹配循环（**不得**复用其 `error.TargetBlockNotFound`，记不上即静默跳过）；
- 动作：`self.last_loop_fallthrough_idx = hop_idx;` **`self.last_loop_fallthrough_src_idx = exit_idx;`** —— 后者与直接位置支**语义不同**：直接位置支里出口块**就是** merge，回落边来源要回到「循环诸块中真正 `br`/`cbr` 到它的那块」（故用 `findExitEdgeSourceIdx`）；一跳情形里 merge 是**出口块的目标**，写这条边 PHI 的前驱正是**出口块自身**（`:8884–:8893` 消费者按 `src` 块取 PHI 入边，实测干净代次 `fbe6382a` 该块为 `if (self.last_loop_fallthrough_src_idx) |lsrc| {` `:8884` → `materializeBrTargetMergePhis(writer, func.blocks.items[lsrc], func.blocks.items[lfi], body_indent)` `:8886–:8891` → 收口 `:8893`），故 `src = exit_idx`，不得复用 `findExitEdgeSourceIdx`；
- 返回值：**不改**（仍是通用路径的 `:15026 return exit_idx + 1`；新增支不 return），**不改 `then_end`**、不改 `:8837–:8854` 帧界求解（那是 R5/R6/R7/R8/R11 五度否证的面）。

**改动二（行走侧，`generateLabelDrivenBlockRange` 的 `for_cond_` 分支返回处，干净代次实测 `:7482–:7485`，派发行 `:7483`；照抄模板为 foreach 侧 `:7471–:7477`）**：镜像 foreach 的帧内停走 —— `defer ∧ lfi ≠ null ∧ (lfi < loop_head_idx or lfi < range_start)` ⇒ `break`，把 `[i, end_idx)` 未走块交还外层。**必须与改动一成对**：R14 已实测「只加改动二」在红形面 0 读数、在语料 `f124` 有 1 次 `stop=1`（ inert + 漂移）。⇒ 本轮若落地，停走谓词应由 **foreach / for 两侧共用一个 helper**（DRY；**while 侧不改**，R14 该面 0 读数），而非在两处复制。**实测窄度归因（§3.20）**：全 150 条读数里 `tk=0 ∧ hoplt=1` 有 38 条，全部由 `defer=0` 排除，语料面剩 2 条又都由更靠前的 `:14923` 支提前返回 ⇒ 谓词的收敛力**单靠 `defer`**，故 `defer` 置位面（坑 5）一旦外扩本候选的零面即失效。

**落地前必须先堵的五条坑（逐条要有读数，不许推测）**：

| # | 坑 | 处置口径 | 状态（实文复核后） |
|---|---|---|---|
| 1 | 一跳出口块若不是**纯转发**（含指令/PHI），`return exit_idx + 1` 已把它 `processed.put` ⇒ 其指令永不发射 | 判据必须再加「`exit_block` 无非终止指令且无 phi」 | **已消解**：通用路径 `:14977–:14981` 本就 `processed.put` + 逐条发射 `exit_block` 指令，新增支不改发射 ⇒ 无指令丢失，原「窄读指令数」前置作废 |
| 2 | 新支覆盖直接位置支 | 写成 `else` 分支（仅直接支为假时求一跳），保持既有 f161 缺陷B / XP8 几何逐字不变 | **已消解**：`:14923`/`:14940`/`:14951` 三支各自提前 `return`，新增支插在其后，互斥关系由控制流保证，无需 `else` |
| 3 | **一跳目标本身是循环头**（`:14996–:15021` 已实证的 `for_exit_ → foreach_cond_` 负环检测几何；此时通用路径会递归派发该循环） | 判据必须排除 `isLoopHeadLabel(hop_block.label)`（`:8874` 消费者已在用同一 helper，口径一致），否则改动二的 `lfi < loop_head_idx` 会把**内嵌循环**当作交还目标 | **新增，必须落地**；R15 `[R15-X]` 的 `hlbl` 字段正是为此采集 ⇒ §3.20 逐事件按标签前缀分类，语料若出现循环头前缀即证「必须排除」，若全为 `if_merge_`/`logical_merge_` 一类则排除支仍写死（防御性，成本 1 句） |
| 4 | 交还后兄弟臂由谁发射 | 依赖 `:8865` 消费者把 `merge_bi` 交还后的既有「乱序双臂模板」（R9-B 已实测 `nmi < nti` 路径可用）；复测点 = 形 9 从「三臂顺序执行」变「只走 one arm」，若变「臂丢失」则说明交还几何不匹配 ⇒ 属否证，不落地 | 待定（落地批复测项）。**静态支撑三条（实测行号，非读数）**：(i) 停走用 `break` 而非 `return` ⇒ 不走 `:7449–:7453` 的 `markReachableRestBlocks` 整段吞标，块 7/8 天然留在 `processed` 之外；(ii) 消费者在 `:8880–:8881` **先清** `return_generated`/`break_generated` 再交还 `merge_bi` ⇒ 外层后续扫描不会把兄弟臂判为不可达；(iii) R9-B 批实测同一 handler 的 `nmi < nti` 乱序双臂模板在形 4 上可用（`same=7`）。**最终判定仍只能在落地批以九形门 stdout 做** |
| 5 | `defer_loop_fallthrough` 置位面 | **禁止外扩**（既有绑定约束）；本候选只在已置位的情形下细化目标，不改任何置位点 | 约束保持 |

**验收目标（落地批）**：九形门 `same=8 differs=1`（形 9 转绿；形 7 仍红，R12 已证其不属本路线）；D 旁门 `2/2`、C005 `17/17`、RC-4 `3/1`（红点仍 REF-003）、RC-5 `IDENTICAL`、do-while `2/2`、硬零漂移 `diff=0`、官方 68 `PASS 67 / FAIL_* 0`、巡检 `mismatch=0`、抽查 `ok=5`、`zig build test 326/326`。**且按流程规约 (a)：先有 §3.20 全量语料面读数，实现必须逐字等于实测规则。**

**落地模板预写（**未落地**；标识符已逐字核对 `fbe6382a`/32797 实文，点头后按此实现，任何偏离须先补读数）**：

```zig
// native_linker.zig —— ① 共用谓词（新增私有方法，紧邻 generateLabelDrivenBlockRange 之前）
/// 臂内联上下文帧内停走谓词（CODEGEN-006 §4.7）：本循环派发把出口（或出口一跳目标）
/// 交还给排在循环头/本帧起点之前的乱序共享 merge 时，臂 range 必须立即停走，
/// 未走块交还外层 if 发射。foreach/for 两个派发分支共用，禁止复制口径。
fn armFallthroughStop(self: *const Self, loop_head_idx: usize, range_start: usize) bool {
    if (!self.defer_loop_fallthrough) return false;
    const lfi = self.last_loop_fallthrough_idx orelse return false;
    return lfi < loop_head_idx or lfi < range_start;
}

// ② 改动一（generateForFromLabels，:14975 之后 / :14977 之前）
// 一跳回落记录（形 9 族）：出口块排在循环头之后，但其 .br 目标在循环头之前
// （乱序共享外层 merge）。:14923 直接位置判据看不到这一跳 ⇒ lfi 留空 ⇒
// ③ 的帧内停走与 :8865 消费者均无从触发，兄弟臂被真臂吞并。
// 口径复制 foreach 侧既有的一跳记录（:12962–:12972，cleanup .br 目标 → ni）。
// 只记录，不改 processed 标记、不改发射、不改返回值（通用路径照旧消费出口块）。
if (self.defer_loop_fallthrough) {
    if (exit_block.terminator) |term| {
        if (term == .br) {
            const hop_idx: ?usize = blk_hop_c006: {
                for (0..func.blocks.items.len) |hi| {
                    if (func.blocks.items[hi] == term.br) break :blk_hop_c006 hi;
                }
                break :blk_hop_c006 null;
            };
            if (hop_idx) |hi| {
                if (hi < cond_idx and !self.isLoopHeadLabel(func.blocks.items[hi].label)) {
                    self.last_loop_fallthrough_idx = hi;
                    self.last_loop_fallthrough_src_idx = exit_idx;
                }
            }
        }
    }
}

// ③ 改动二（generateLabelDrivenBlockRange，:7482–:7485 for_cond_ 分支）
if (std.mem.startsWith(u8, label, "for_cond_")) {
    const loop_head_idx = i;
    i = try self.generateForFromLabels(writer, func, i, end_idx, cleanup_regs, processed, loop_label_counter, indent);
    if (self.armFallthroughStop(loop_head_idx, range_start)) break;
    continue;
}
```

foreach 分支 `:7471–:7477` 的内联条件同改为 `if (self.armFallthroughStop(loop_head_idx, range_start)) break;`（等值改写，非行为变更；DRY 规约要求）。**while 侧（测试行实测 `:7488` `while_cond_` / `:7495` `while_body_`）不改** —— R14 实测 WHC/WHB 两站点在红形面 0 读数，无读数支持的外扩禁止。（`while_body_` 行号原引 `:7494` 属 off-by-one，`:7494` 为该支注释行；§3.22.1 复验更正。）

**模板标识符复验（2026-10-05 只读，当前代次 `fbe6382a`/32797 实文，逐条给行号，非推算）**：

| 模板片段 | 复验依据（实测该行内容） | 判定 |
|---|---|---|
| `exit_block.terminator` / `term == .br` / `term.br` | `const exit_block = func.blocks.items[exit_idx];` `:14915`；同形用法 `if (exit_block.terminator) \|term\| { if (term == .cond_br)` `:14940–:14941`；`.br => \|br_target\|` `:14996`；`tt.br`/`ct.br` 载荷取法 `:371`/`:501` | 可用 |
| `func.blocks.items[hi] == term.br`（指针相等） | 既有同idiom `for (0..func.blocks.items.len) \|i\| { if (func.blocks.items[i] == br_target) break :blk i; }` `:15005–:15010` | 可用；**新支不得复用其 `return error.TargetBlockNotFound`**（找不到即静默不记录） |
| `cond_idx` / `exit_idx` 在插点仍在作用域 | `:14923` 的 `exit_idx < cond_idx`、`:14928` 的 `findExitEdgeSourceIdx(func, &[_]usize{ cond_idx, body_idx, loop_idx }, …)` 均位于同一函数体 | 可用 |
| `self.isLoopHeadLabel(label: []const u8) bool` | 定义 `:25641–:25652`，签名 `fn isLoopHeadLabel(self: *const Self, label: []const u8) bool`，宽集含 `foreach_increment_`/`for_loop_` | 可用（坑 3 的排除支） |
| `self: *const Self` 接收者 | 全文件已用 16 处 | 可用（helper 声明口径） |
| for 分支插点 `:7482–:7485` | 实文 `if (std.mem.startsWith(u8, label, "for_cond_")) {` `:7482`，派发行 `:7483`（**无** `loop_head_idx`，须随改动二新增一行），`continue;` `:7484` | 一致 |
| `range_start` 在 `generateLabelDrivenBlockRange` 作用域 | foreach 停走已在用 `lfi_w < loop_head_idx or lfi_w < range_start` `:7473` | 可用 |
| 三支提前 return ⇒ 新支互斥 | `:14935 return exit_idx;`、`:14943 return exit_idx;`、`:14971 return exit_idx;` / `:14974 return exit_idx + 1;` ⇒ 控制到 `:14977` 时终止符必为 `.br`（或无） | 成立（坑 2 消解实证） |
| helper 插入点「紧邻 `generateLabelDrivenBlockRange` 之前」 | 实文 `fn generateLabelDrivenBlockRange(` `:7431`，接收者 `self: *Self` `:7432`；上一函数 `warnEmptyElseBeforeUnreachable` 收于 `:7429`，`:7430` 为空行 ⇒ 新 helper 落在 `:7430` 之前/之后均可，实测写法为插在 `:7429` 与 `:7431` 之间 | 一致；helper 用 `*const Self` 而宿主用 `*Self` ⇒ 可调用，无接收者类型冲突 |
| 坑 4 (i) 的实文实证：`break` 不落整段吞标 | 吞标只有一处且**在 while 头部**：`if (self.return_generated or self.break_generated)` `:7449` → `try self.markReachableRestBlocks(func, i, end_idx, processed);` `:7452` → `return;` `:7453`；函数体自 `while (i < end_idx)` `:7446` 直至 `:10930`，**while 之后到函数尾 `:10931` 之间无任何后处理语句**（实文只剩 `i += 1;` `:10929` 与两个闭合括号）⇒ 从 `:7482` 分支 `break` 即干净返回，剩余块天然留在 `processed` 之外 | 成立 |
| 消费者侧行号（R13 读数为插桩代次，此处为干净代次 re-grep） | 递归行走 `:8859` ⇒ 守卫 `if (self.last_loop_fallthrough_idx) \|lfi\|` **`:8865`** ⇒ 五条件 `lfi_is_join` **`:8871–:8876`** ⇒ 动作 `merge_bi = lfi` `:8878`、`processed.remove(lfi)` `:8879`、清 `return_generated` `:8880`、清 `break_generated` `:8881`、PHI 物化块 `:8884–:8893` ⇒ 交还后清 `lfi` `:8897–:8898` | 与 §4.7 正文所引 `:8865–:8895` 逐字吻合，无需更正 |

## 5. 验收门（修复落地时）

1. **本单门（终态）**：`c006_tl_probe_run_tmp.sh` ⇒ `total=9 same=9 differs=0`（**A + D 批**落地实测 `same=6 differs=3`；**R9-B 批（IPD 结构 merge，§3.14）落地实测 `total=9 same=7 differs=2`（2026-10-05，形 4 转绿、无新红）**；余 7/9 两形：形 7 链节点 `IPD=null` ⇒ 结构路线无覆盖，形 9 需 C 站点判据而该面语料命中 5/10 非 0 ⇒ **不落地**；可达路径见第 4 条；逐门读数见 §4.2、§4.3、§3.14）。
1.1. **D 批旁门（取臂面，勿并入 9 形门）**：`c006_d_probe_run_tmp.sh` ⇒ `C006_D_GATE_DONE total=2 same=2 differs=0`。形 8 同几何分别取末节点 then 臂（D-1 `T10 b4`）与链首臂（D-2 `T11 b2`），逐字节等值 ⇒ 否证「双臂发射把 then 臂落进 else 臂体 / 首臂串跑」。探针登记见 §1.1。
2. 回归门不得劣化：17 形等值门 `same=17/17`、RC-4 门 `same=3 differs=1`（唯一红点归 REF-003）、RC-5 八形合串 **`IDENTICAL`**、do-while 门 `same=2/2`。**A 批轮实测（2026-10-04）逐门等于基线**：`PROBE_DONE total=17 same=17 differs=0`、`RC4_PROBE_DONE total=4 same=3 differs=1`（红点仍为 `ref003_crash_attr_tmp`，段错误归 REF-003）、RC-5 合串 `IDENTICAL`、`DOWHILE_PROBE_DONE total=2 same=2 differs=0`。**D 批轮实测（2026-10-04，同一串行门串）逐门仍等于基线**：`PROBE_DONE total=17 same=17 differs=0`、`RC4_PROBE_DONE total=4 same=3 differs=1`（红点仍是 REF-003）、RC-5 八形合串 `IDENTICAL` + F-B/F-H 单形 `IDENTICAL`、`DOWHILE_PROBE_DONE total=2 same=2 differs=0` ⇒ 双臂发射未污染既有几何。**R9-B 批实测（2026-10-05，仍等于基线）**：17 形 `same=17 differs=0`、RC-4 `same=3 differs=1`（红点仍 REF-003）、RC-5 `IDENTICAL`、do-while `same=2/2`、**D 旁门 `same=2/2`**、`ref001_probe_run_tmp` `same=1 differs=3`（逐字等于 2026-09-30 登记基线）⇒ IPD 选路未污染任何既有几何。
3. 官方 68 回归 `FAIL_* = 0`；冻结基线漂移 `diff=0`；确定性巡检 `mismatch=0`；抽查 `ok=5 bad=0`；`zig build test` 全绿。**A 批轮实测（2026-10-04，全部达成）**：漂移 `DRIFT_DONE total=68 ok=68 diff=0 notemp=0 norow=0`、官方 `TOTAL 68 / PASS 67 / SKIP 1 / FAIL_* = 0`（SKIP = `f004`，`PHP_error_exit=255` 的既有排除项）、巡检 `SWEEP_DONE total=68 mismatch=0 notemp=0`、抽查 `SPOT_DONE ok=5 bad=0`、`zig build test --summary all` = `21/21 steps succeeded; 326/326 tests passed`。**D 批轮实测（2026-10-04，全部达成）**：漂移 `DRIFT_DONE total=68 ok=68 diff=0 notemp=0 norow=0`（硬零门成立，R5 实测该站点 `be=0` 语料命中面 0 ⇒ 任何漂移即为意外扩散）、官方 `TOTAL 68 / PASS 67 / SKIP 1 / FAIL_* = 0`（SKIP 仍为 `f004`）、巡检 `SWEEP_DONE total=68 mismatch=0 notemp=0`、抽查 `SPOT_DONE ok=5 bad=0`、`zig build test --summary all` = `21/21 steps succeeded; 326/326 tests passed`。**R9-B 批实测（2026-10-05，全部达成）**：漂移 `DRIFT_DONE total=68 ok=68 diff=0 notemp=0 norow=0`（与 R9 影子轮预算的语料面 0 逐字吻合 ⇒ 无意外扩散）、官方 `TOTAL 68 / PASS 67 / SKIP 1 / FAIL_* = 0`、巡检 `SWEEP_DONE total=68 mismatch=0 notemp=0`、抽查 `SPOT_DONE ok=5 bad=0`、`zig build test --summary all` = `21/21 steps succeeded; 326/326 tests passed`、`timeout 560 zig build` rc=0，另加编译开销四脚本实测（§3.14 表）⇒ 无负向优化。
4. **本单门按批次分级（R5 实测口径，§3.6.5）**：A 批 ⇒ `total=9 same=5 differs=4`（1/5/6 转绿；2/3 原绿形不得劣化）；A + D 批（`chain_unwind` 裸 break 按臂派发，§4 D 行）⇒ `same=6 differs=3`（+8）**── 已于 2026-10-04 D 批轮精确命中（预测早于实现写死，实测 `C006_TL_GATE_DONE total=9 same=6 differs=3`，形 8 转绿，见 §4.3）**；余 3 形（4/7/9）**原前置「臂归属判据」已由 R6 否证**（§3.7），改前置为**臂重联判据 R7**（§3.7.3 / §3.8）**⇒ R7 已完成并第三次否证（§3.9）**，未出二分读数前禁止改 `.cond_br` 双臂的区间或出口语义 ⇒ 三形保持红属**预期**，不得按终态门判定批次劣化。**新的唯一前置 = §3.10 生成码侧结论**：链第二级 `cond_br` 的**终止符根本没被派发**（生成码里连 `if (` 都没有，条件寄存器无消费者），要查的是**只发指令、不发终止符的内联臂发射器**（`:7229–:7243` 一类只看 `.br` 的 terminator 盲区），而非区间/归属/重联 ⇒ R8 轮。**R4 记录的「两处未闭合口径」（形 7 错臂路径、形 8 `chain_unwind` 站点）已由 R5 闭合**（§3.6.2 / §3.6.4）。

**门 4 锚点的现行 re-grep 补注（2026-10-05 只读，代次 `fbe6382a`/32797；原引 `:7229–:7243` 属 `3ae7b34e`/32546 代次，现已失效）**：当前树里「只看指令、不看终止符」的内联发射器共两枚 —— ① **`emitBlockInlinedWithPhiFrom` `:7244–:7270`**，函数体仅 `for (blk.instructions.items)`（`:7251`）+ PHI 按边物化，**全文未出现 `blk.terminator`**（实测 grep 命中 0），调用站点 `:8300`、`:9878`；② **`emitSpilledNestedIfMerge` `:7281` 起**，其文档注释 `:7279` 自陈「**外层 merge 不发射终止符、不标记已处理**」，调用站点 `:7972`、`:8330`、`:16310`。⇒ 形 7 若走「臂守卫坍缩」路线，取证站点候选即这五处调用；**本轮零插桩、零编译，判定形 7 实际经过哪一处仍需授权后的窄探针轮**（不许静态推测）。
4.1. **批次阶梯实测补记（R9-B 批，2026-10-05 已命中）**：A 批 `same=5` → A+D 批 `same=6` → **A+D+R9-B 批（IPD 结构 merge，B 站点选路，§3.14）`C006_TL_GATE_DONE total=9 same=7 differs=2`（形 4 转绿、无新红）** ⇒ 本单门终态由 `same=9` 改为**分阶段**口径，余 **2** 形（7/9，注意已不再是 3 形）另立前置：形 7 的链节点 `IPD=null`（then 臂以 `ret` 收尾 ⇒ 仅虚拟出口后支配）属结构路线**无覆盖**，需换机制；形 9 需 C 站点判据而该面语料命中 5/10 非 0 ⇒ 第五次同位置否证。两形的候选判据不得再从「区间/归属/重联/计数」四类同层取（R6/R7/R8/R8.1 已四轮否证），改由 §7 结构性长期项行承担裁决。
5. **影子实测前置（流程规约 (a)）已跑满四轮**：R4 全 88 脚本（§3.5）⇒ A 谓词锁定「窄四前缀 + 回边/latch 排除」，**语料命中面 0**；R5 全 96 脚本（§3.6）⇒ 否证 PC 原口径、新立 D 类（语料面 0）；R6 全 114 脚本（§3.7）⇒ 否证臂归属口径；**R7 全 113 脚本（§3.9）⇒ 否证臂重联口径（命题站点在红形上零触发 + 派生字段按构造恒定）** ⇒ 区间/归属/重联三类判据全部出局。A/D 两批的漂移门为**硬零门**（`diff=0` 是必要条件，非仅"不劣化"）；B/C 侧任何"先落地再回归"的尝试均已被四轮读数否证，禁止 —— 但 §3.10 表明四轮探针都装在**错层**（派发帧的区间侧），真正的盲区在**内联臂发射器的 terminator 分派**，属新命题、需新判据（R8），不构成对前三轮否证的推翻。**补记（2026-10-05）**：规约 (a) 的前置影子轮累计已跑 **R4/R5/R6/R7/R8/R8.1/R9 七轮**，其中 **R9 为首次取得可落地判据的一轮**（新谓词 = `nmi` 存在 ∧ `nmi>=nti` ∧ `M=IPD(ei)` 存在 ∧ `M∈[start_idx,end_idx)` ∧ `M<nti`；实测九形面 1 命中＝仅形 4、绿语料面 **0/68**）⇒ 据此落地的 R9-B 批免除了「先落地再回归」禁令（禁令的适用对象是四类同层静态判据，不适用于已出语料面 0 读数的新判据）；落地后漂移 `diff=0` 与 R9 预算的语料面 0 逐字吻合，构成规约 (a) 的正向闭环样本。

## 6. 对 AOT-PERF-001 的更正（必须同批记账）

**（本段为 A 批落地前的历史判定，现已被本节末尾「到期兑现」取代）**`perf001_hotspot_probe_tmp.php` 的 **mode=1（顶层全局循环）读数作废**：AOT 侧那条臂从未执行 ⇒ 0.42s 是空跑，不能作为「全局按名寻址」耗时基线。mode=2（函数内局部，1.66s）/ mode=3（数组写，2.56s）不受影响，仍可用于热点归因。⇒ H1 的实测改由 mode=2/3 + 剖面采样承担，见 AOT-PERF-001 §3 更正。

**R4 补证（2026-10-04 实测）**：影子轮在 `perf001_hotspot_probe_tmp` 的 `:10089` 臂尾站点读得 `[S06A] arm=else tgt=for_cond_10 lh=1` ⇒ mode=1 空输出**确由 A 类缺失派发**造成（与形 1 同站点同判据），不是探针写法问题。⇒ **A 落地后必须复测 mode=1**，若恢复输出则该读数可回填 H1 基线（本节的作废判定届时需改为「限期作废」）。

**到期兑现（2026-10-04，A 批落地后复测，本节作废判定改为「已回填有效」）**：同一探针、同一档位（`--optimize=release-fast --no-debug-info`，`n=30_000_000`）——

| mode | AOT | PHP 真值 | 输出 |
|---|---|---|---|
| 1 顶层全局循环 | **6.57s**（原 0.42s 为空跑，已废） | 0.28s | `M1 g=449999985000000 h=90000000` 逐字节等值 ⇒ **该臂现已执行** |
| 2 函数内局部循环 | 1.59s | 0.20s | `M2 …` 等值 |
| 3 数组写循环 | 2.46s | PHP 在 `n=30M` 触 128M 内存上限 Fatal ⇒ 无 PHP 侧可比真值 | `M3 sum=450000015000000` |

⇒ **H1 净成本 = mode1 − mode2 = 4.98s / 30M ≈ 166 ns/迭代**（同一循环体仅局部槽换成全局按名寻址）。mode=2/3 与旧读数（1.66s/2.56s）之差在单次量测噪声内 ⇒ A 批未改变函数内与数组路径性能。完整记录与推论见 AOT-PERF-001 §3.1。

## 7. 待裁决（§六：涉发射侧共享语义与设计决策，未经点头不动手）

| 优先级 | 事项 | 影响面（R4 + R5 实测） | 落地成本 |
|---|---|---|---|
| ~~P0~~ | ~~是否开 **trace 取证轮**~~ | **已完成（2026-10-04）**：R1（行走/派发层 16 探针）+ R2（行内 `.cond_br` 处理器 7 探针）+ R3（clean 轮还原复验），读数见 §3.3/§3.4 | 已支出，无遗留 |
| ~~P0~~ | ~~是否开**修复面前置影子轮**（规约 (a)）~~ | **已完成（2026-10-04）R4**：全 88 脚本六探针，`drift_ok=68 drift_diff=0 compile_fail=0`，读数与判别性判定见 §3.5 | 已支出，`native_linker.zig` 已还原并复验（§3.5.6） |
| ~~**P0**~~ | ~~**A 类修复**：四处臂尾 `.br` 补「目标为**窄循环头**则派发」，按 §4.1 helper（谓词 = `for_cond_`/`while_cond_`/`foreach_cond_`/`do_while_body_`，**禁用宽 `isLoopHeadLabel`**）~~ | **已落地并实测（2026-10-04，§4.2）**：helper `:991` + 四站点 `:9106/:9151/:10068/:10112`（`+65/−4`；**行号为 A 批代次 `22a217f0` 实测**，D 批 `9490bf9f` 插入 helper 后 re-grep 现为 `:9152/:9197/:10119/:10163`，helper `:991` 未变）。本单门 `same=5 differs=4`（1/5/6 转绿，预测精确命中）、**漂移 `diff=0`（68/68 逐字节零漂移，硬零门达成）**、官方 68 回归 `FAIL_* = 0`、确定性 `mismatch=0`、`zig build test` 21/21 & 326/326、五道探针门逐门等于基线；顺带兑现 PERF-001 mode=1（§6）。**状态：A+D 批同处工作区未暂存，未提交（待「提交」指令）** | 已支出 |
| ~~**P0**~~ | ~~**D 类修复**（形 8）：`chain_unwind` 非守卫分支的裸 break `if (!else_is_back_edge) break :chain_unwind;`~~ | **已落地并实测（2026-10-04 D 批轮，§4.3）**：取证轮已由 R5/#61 闭合（站点是缺失派发点 + 语料命中面 0），形态口径由静态侧证 + 两条取臂面探针实测确定为**双臂**（`if (cond) { then 臂 [cti, ei) } else { else 臂 [ei, end_idx) }`，then 区间必须以兄弟 else 块为界，否则线性吞并 ⇒ 即 C 类同因）。落地：helper `emitChainUnwindArmPair` `:1035`（代次 `9490bf9f` 实测）+ 两处孪生站点 `:9245` / `:10211`（`+58/−2`；两站点原 `break :chain_unwind` 前语义不变 ⇒ 形态不符仍维持不发）。门：**本单 `same=6 differs=3`（形 8 转绿，精确命中 §5 门 4 预测）**、新 D 旁门 `total=2 same=2 differs=0`、**漂移 `diff=0`（68/68 硬零门）**、官方 68 `PASS 67 / SKIP 1 / FAIL_* = 0`、巡检 `mismatch=0`、抽查 `ok=5 bad=0`、`zig build test` 21/21 & 326/326、五道回归门逐门等于基线；`zig build` rc=0（70s）。**覆盖边界**：只证到三级链末节点取双臂；形 4/7/9（B/C 类）不受本批影响，仍红属预期。**状态：工作区已落地（未暂存），未提交（待「提交」指令）** | 已支出 |
| ~~P1~~ | ~~**R5 细影子轮**（形 7 有序分支 else 取用 + 形 8 `chain_unwind` 臂尾站点）~~ | **已完成（2026-10-04）**：12 标签 / 17 站点，三代次插桩下 15 永久探针 `main.zig` 逐字节不变，全量 `drift=OK 68/68`、`compile_fail=0`、`rows=96`；还原复验 7 项全等 + clean 重建 `rc=0/65s` + 五门读数与插桩前一致（§3.6） | 已支出。**三项闭合结论**：PB 收紧判据仍命中 2 个通过脚本、PC 原「以 `else_bi` 为界」被 `inh` 全 0 否证（语料面 4）、PD 语料面 0 ⇒ 新立 D 类 |
| ~~P0~~ | ~~**臂归属判据设计轮**（取代原「区间以兄弟臂为界」P1）：形 4/7/9 需可证伪的「某块是否属于本 `cond_br` 的 else 臂（沿链可达）」判定，再谈区间语义~~ | **已完成并否证（2026-10-04，R6 / #59）**：4 标签 / 5 站点，114 脚本，`drift_ok=68 drift_diff=0 compile_fail=0`；命中面 12 事件 = 红 3（形 4/7/9）+ 绿 9（f025/f043/f067/f072/f080/f095/f124 + `ref002_r1b` ×2），四个字段无一能二分；C3/CD 零命中 ⇒ **区间侧（上界 + 归属）已无候选判据**（§3.7） | 已支出，`native_linker.zig` 已还原复验（7 项全等）+ clean 重建 64s + 五门读数不变 |
| ~~**P0**~~ | ~~**臂重联判据影子轮 R7**（§3.7.3）：改问「then 臂内完成循环派发后，本节点 else 目标能否重联成 `} else {`」；在 `then_indirect_to_else` 两出口与帧递归出口读 `else_branch_start==null`、`else_bi` 终止符 tag、`then_end==end_idx` 兜底、派发后 `merge_bi`/`processed` 对 else 臂归属~~ | **已完成并第三次否证（2026-10-04，§3.8.6/§3.9）**：8 标签 / 113 脚本，`drift_ok=68 drift_diff=0`；命题指定的两处作用点（直派出口 `[S08T2]`、五条件 `[S08T1C]`）在三个红形上**零触发**，孪生站点关键派生字段**按构造恒定**（`else_in_rng` 47/47 恒 false、`else_bi<nti` 48/48，因外层 `else_bi` 与嵌套 `nti` 节点错配）⇒ 区间/归属/重联三类判据在本函数内**搜索穷尽** | 已支出，`native_linker.zig` 已还原复验（7 项全等）+ clean 重建 `rc=0/73s` + **六门读数逐门等于基线**（§3.9.4） |
| ~~**P0**~~ | ~~**R8 内联发射器 terminator 盲区取证轮**~~ | **已完成并第四次否证（2026-10-05，§3.11 + §3.12）**：七枚探针全量影子（`S09_SHADOW_DONE total=105 … drift_diff=0`）+ 两枚收紧探针窄面（`R81_DONE total=73 … drift_diff=0`）⇒ 立项口径「红 3 命中 / 语料 0 命中」**不成立**（R8-a 语料面 1＝f067，R8-b 语料面 4＝f056/f095/f102/f124，其中 f124 与形 9 逐字段同构），收紧侧四条候选判据（P-a1/P-a2/P-cnt/P-bound + 反向字段单独面 4 事件）全部否证 ⇒ **区间/归属/重联/计数四类静态判据在本函数内搜索穷尽**，硬要求未满足 ⇒ 4/7/9 **不落地** | 已支出（插桩代次 `24b41b37…`/32710、`4f29ae2d…`/32792 均已还原），详见 §3.13 收尾记录 |
| ~~P0（立项原文，保留供 4/7/9 覆盖面追溯）~~ | **本族 4/7/9 转结构性长期项：三条落地路线选一**。①**链级双臂显式发射**（改动局限在 `.cond_br` 处理器的选路条件。谓词按 §3.13 更正口径 = 「本链 else 目标块为**真实臂**（终止符 `br`/`ret` 而非 `cond_br` 链节点）**且**其 `br` 目标 `<` 帧起点（反向 merge ⇒ 帧内无收口站点）」，原「两臂尾同目标」写法已被实测否证 ⇒ 复用既有 `emitChainUnwindArmPair` `:1035`（re-grep 实测），不新增机制，DRY）；②**链 arms/merge 归属进 IR**（`Terminator.cond_br` 增 `merge_block`，或发射前只读建 `chain_id → {arms, merge}` 表 ⇒ 根治，但触碰 IR 与 optimizer 全线，需重冻结基线）；③**帧收口站点回传**（`generateLabelDrivenBlockRange` 增「帧停止块」返回值，外层据此续发兄弟臂，即把 f124 修复13 的 `return_generated` 复活机制推广到 `br`-回落形态） | ①影响面最小（本函数选路 + 一次全量影子门），但「else 臂尾反向 merge」这一字段单独在绿语料面为 4（f032/f070/f124/f163），且「else 块是否为 `cond_br`」只二分得动「形 4 vs f067」，对形 7（`ttag=ret`）/形 9（else 目标块本身即 `cond_br`）**无覆盖** ⇒ ①的真实覆盖面可能仅 1–2 形；②最彻底、能把五轮同层试错一次性终结，代价是 IR 扩字段 + 基线重冻结 + 全门复跑；③改动跨 3 个调用层（返回签名波及），回归面中等 | ①约 1 轮插桩 + 1 轮影子 + 1 次落地（≈40 min）；②**两条子路线代价差一个量级（实测波及，干净树 `9490bf9f`）**：扩 `Terminator.cond_br` 字段 ⇒ `grep -c '\.cond_br = \.'` = **ir_generator 19 处构造点**必须逐处填字段（Zig 匿名结构体字面量无默认值 ⇒ 漏一处即编译失败），另 `optimizer.zig` 19 处、`native_linker.zig` 读点 **300 处**、6 个测试文件需复验 ⇒ 半天～1 天且回归面最大；**发射前只读建表**（`chain_id → {arms, merge}`，不动 IR）⇒ 只在 linker 内加一次预扫描 + 三处选路改读表 ⇒ 约 2–3 小时，且天然满足规约 (a) 的影子门；③约半天～1 天（**实测波及面 = `generateLabelDrivenBlockRange` 调用站点 94 处**，`grep -c` 于干净树 `9490bf9f`；若改返回类型需逐站点适配，若改用 `self` 字段传出则必须为递归做 save/restore ⇒ 易碎，与 §3.11「插桩零行为改动」同层的隐式状态风险）。**未获裁决前不动编译器源码**（该立项已于 2026-10-05 由下行裁决并按 2′ 部分落地） |
| ~~**P0**~~ | ~~**本族 4/7/9 转结构性长期项：三条落地路线选一**（①链级双臂显式发射 ②链 arms/merge 归属进 IR / 发射前只读建表 ③帧收口站点回传）~~ | **已裁决并按 2′ 落地 B 站点子集（2026-10-05，R9-B 批，§3.14 + §4.5）**：实际取路线 **2′ 的即时变体** = **不扩 IR、不预扫描建表**，改在 `.cond_br` 选路处**就地求链节点的结构 merge**（新 helper `findChainMergeByPostDom` `:1080`，Cooper-Harvey-Kennedy 后支配跑在【反向】CFG，显式栈后序 DFS ⇒ 零新增递归风险），复用既有 `nmi < nti` **乱序双臂模板** ⇒ 不新增发射形态（DRY，符合「不触碰 IR 与 optimizer」的代价约束）。落地判据（R9 影子轮实测语料面 0/68 后才写码）：`nmi` 存在 ∧ `nmi>=nti` ∧ `M=IPD(ei)` 存在 ∧ `M∈[start_idx,end_idx)` ∧ `M<nti` ⇒ merge 改判 `M`。门实测：**本单 `C006_TL_GATE_DONE total=9 same=7 differs=2`（形 4 转绿，精确命中 §5 门 4.1 阶梯预测）**、D 旁门 `same=2/2`、c005 17 形 `same=17/17`、RC-4 `same=3 differs=1`（红点仍 REF-003）、RC-5 `IDENTICAL`、do-while `2/2`、ref001 `same=1 differs=3`（等于 2026-09-30 登记基线）、**漂移 `DRIFT_DONE total=68 ok=68 diff=0`（硬零门）**、官方 `TOTAL 68 / PASS 67 / SKIP 1 / FAIL_* = 0`、巡检 `mismatch=0`、抽查 `ok=5 bad=0`、`zig build test` 21/21 & 326/326、`timeout 560 zig build` rc=0；插桩残留 `grep -c S10` = 0。**状态：工作区已落地（未暂存、未提交，待「提交」指令）** | 已支出（helper 区 117 行 `:1073`–`:1189` + B 站点 17 行替换 1 行 `:10180`–`:10196` = `+134/−1`，实测见 §4.5；负向优化红线实测见下行） |
| **P0（待老铁裁决）** | **余 2 形（7/9）+ 遗留四项（c/d/e/f）的下一步口径，选一揽子授权或逐条点头**。a) **形 7**：链节点 `IPD=null`（then 臂以 `ret` 收尾 ⇒ 仅虚拟出口 V 后支配）⇒ 结构 merge 路线**无覆盖**，需换机制（候选回到 §3.10 的「臂守卫坍缩」本体，属新命题需新判据）。**〔R16 实测更正（2026-10-05，§3.21，零插桩、零源码改动）：本项原诊断被推翻〕** 形 7 的真实症状不是「守卫坍缩后错臂执行」，而是**二级 `cond_br` 的终止符从未派发**（生成码 `:159` 算出 `reg_8` 却无任何消费者）+ **末臂 `[if_else_4, for_cond_7, for_body_8, for_exit_10]` 整体未发射**（`"T7 hit="`/`" sum="` 常量零引用、函数体 `for`/`while` 计数 0）；且 IR 侧实测该链**根本没有 `if_merge_` 块**（13 探针普查：仅 `c006_tl_fncontext_loop` = 0，其余 12 支 = 1）⇒ `merge_bi`/IPD/`defer`/`lfi` 机制族对形 7 **原理上无对象** ⇒ 形 7 由 C 类**改判为 A/D 类**（缺失派发），与 §3.10「terminator 盲区」为同一命题；a′) **R17 窄探针取证轮 = 形 7 的唯一合法前置（待点头，范围已由 §3.21.1 更正）**：原「在五枚内联发射站点读出二级 `cond_br` 被哪一站点吞掉」这一提问**已由 R8 既有逐字读数答复并作废** —— 形 7 的帧 `[3,8)` 走的是 `nested_then_idx` 兜底**线性摊平** + 块 3 的 `ret` 冒泡触发 `markReachableRestBlocks` 吞标（`:7449–:7453`），与五处内联发射器无关 ⇒ 重装探针再问它是浪费一轮。**重定义后的 R17** = 单枚 `ttag`（本链 then 臂终止符类别）面探针轮：站点 = R8.1 `S09N` 同处，候选判据 = `R8-a 四条件 ∧ ttag=ret`（`ttag` 从未进入任何合取），**其语料面当前 = 未知**（R8.1 原始日志已按产物规约删除，禁止凭记忆外推），**原前置「开轮前须确认该站点在当代次可复现原读数」已由 §3.21.2 只读实文核对完成（零插桩、零编译）** —— 站点 = else 侧链处理器 `nested_then_idx` 兜底摊平支，当前代次实测 `:10178`（binder `nti`）/`:10179`（进入守卫）/`:10180`+`:10189–:10196`（R9-B 的 `blk_p9` IPD 改判，blame `497edc6`）/`:10197`/`:10202`（`cs18_end`）/`:10214`（线性摊平调用本身），blame 实证其余五处早于 R8.1 且一字未改 ⇒ 六字段全可绑定，打印点只取 `ttag` 时置于 `:10197` 前、要复现原六字段全行须移至 `:10202` 后（`cs18_end`/`narm` 依赖帧上界）；一枚 tag、只读、stderr-only，并按规约 (a) **先测语料面**；未见读数前不改码；即便面为 0，动作仍须与 §7 路线 ③ 完整形态同批裁决；b) **形 9**：需 C 站点判据，R9 实测该面语料命中 **5/10 ≠ 0** ⇒ 按规约 (a) **不落地**（第五次同位置否证）；c) **孪生三站点未测** `:9227`/`:9667`/`:10622`（同形 `if (nested_merge_idx) \|nmi\|`）是否同样改判；d) `nmi == null` 的共享 merge 路径是否接 IPD；e) **IPD 无函数级缓存**（每调用重建反向 CFG + DFS + CK 定点；实测全语料仅 24 次调用，四脚本编译 real 10.52/10.61、12.59/12.62、11.08/11.12、12.65/12.66 ⇒ 差在噪声内）；f) 是否把该判据推广到 `generateIfFromLabels` 族同类站点 | a) 覆盖 1 形、需全新取证轮；b) 覆盖 1 形、语料非零面 ⇒ 阻塞；c) 三站点无读数，未测即改违规约 (a)，可合并为一轮影子；d) 影响 `nmi==null` 的全部语料路径，风险最高；e) 纯性能项，改动局限 helper 内（per-function memo），当前无实测退化 ⇒ 可暂缓；f) 波及另一发射器家族，回归面最大 | a) 1 轮取证 + 视读数；b) 1 轮新判据设计；c) 1 轮合并插桩 ≈40 min；d) 1 轮插桩 + 硬零漂移门；e) ≈20 min（含漂移门复跑）；f) 半天～1 天。**未获裁决前不动编译器源码** |
| ~~**P0**~~ | ~~**R10 结构口径外扩影子轮**（对上行的 a/c/d 三项做全 68 语料取数，不引入新机制）~~ | **已完成（2026-10-05，§3.15 + §3.15.1）**：三枚只读探针（`S11A` then 侧孪生选路站点 / `S11B` else 侧已落地 B 站点 / `S11C` 形 9 的 `then_end` 兜底站点）+ IPD 原值四分类（`NONE`/`V`/`SELF`/`M`），净插入 94 行 stderr、**无一字进 `writer`**；中性双证 = 九形门 `same=7` 逐字同判 + 全量漂移 `drift_ok=68 drift_diff=0`。**四问答案**：c) then 侧 10 事件中 `cls=M` 的 9 条**全部 `ipd == nmi`** ⇒ 结构口径在此站点从不给出不同答案 ⇒ **外扩无收益，不改**（闭环）；a) 形 7 的 `cls=V ∧ ge=1` 签名被 **4 个通过脚本复现 5 事件**（f007/f026/f067_min_repro/f102×2，其中 3 条与形 7 **逐字段全等含帧 `[0,8)`**）⇒ **本族第五次否证**，阻塞物移出选路站点；d) `nmi == null` 路径 21 事件 `hit` 全 0 ⇒ **无 IPD 可落地面，不接**（闭环）；b) 形 9 的精确格 `etag=cond_br ∧ cls=M ∧ rel=2` 语料面 0，但两枚邻居格（`cond_br/M/1` 含 `te==end` 兜底 = f095/f124、`br/M/2` 含兜底 = f124）各非零 ⇒ 唯一分隔线是块序 `rel` ⇒ **触自设②号门槛，不落地**。**附带**：四分类穷尽（60 事件 = 32 `M` + 28 `V`，`NONE`/`SELF` 为 0）；`etag`（else 目标块终止符类别）是本轮唯一与 §3.10「臂守卫坍缩」同维的结构字段。**还原复验（十项全绿）**：clean `zig build` rc=0/64s，七探针门逐门等于 R9-B 基线（九形 `same=7`、D `2/2`、c005 `17/17`、RC-4 `3/1`、RC-5 `IDENTICAL`、do-while `2/2`、ref001 `1/3`）+ 漂移 `diff=0` + 官方 `PASS 67/SKIP 1/FAIL_* 0` + 巡检 `mismatch=0` + 抽查 `ok=5 bad=0` + `zig build test` `21/21 & 326/326`| **⇒ R10 不产生落地批次。** 形 7/9 的唯一在途路线 = **2′ 的「链结构表」变体**：linker 内按函数一次性建 `chain 节点 → {臂块集合, 结构 merge(IPD)}`，选路/帧界改读该表（不看块序）。**开轮前须先跑一致性影子**（表派生帧界 vs 现口径帧界，全 68 语料逐字节零漂移才算候选）⇒ 约 1 轮插桩（≈45 min）+ 1 轮落地（≈2 h）；e) IPD 无函数级缓存（实测语料仅 24 次调用、四脚本编译差在噪声内）**仍待裁决**；f) 推广到 `generateIfFromLabels` 族**仍待裁决** |
| ~~**P0**~~ | ~~**R11 链结构表一致性影子轮**（§3.15 末行强制前置：表派生帧界 vs 现口径帧界，全 68 语料逐字节零漂移才算候选）~~ | **已完成并第六次否证（2026-10-05，§3.16）**：插桩代次 `779bda27…`/33060 行、净插入 **`+264/−0`**、stderr-only 无一字进 `writer`；中性双证 = 九形门 `same=7` 逐字同判 + 全量 **`S12_SHADOW_DONE total=68 hit_scripts=25 compile_fail=0 drift_ok=68 drift_diff=0`**。**三条实测否证**：**R11-e**（`then_end := 表派生帧界`）语料面 = **18 事件 / 15 个通过脚本**（12 例收帧含 5 例有损、6 例放帧打在现口径**故意的空帧** `te==fs` 上）；**R11-f**（最窄候选 `ovrA=1 ∧ swuA=1`「无损收帧」）面 = **7 事件 / 6 个通过脚本**（f007/f026/f067_min_repro/f095/f102×2/f124）；**R11-g**（路线 2′ 的 `arms` 半边）`teA != teB` 事件 = **0/35** ⇒ 兄弟臂截止集对帧界**零信息增益**。**同格复现**：形 9 与 f095/f124 在 T1 站点**每个结构字段同格**（`narm=3 ft=br armb=3 m<fs teA==teB ovrA=1 cutA=0 swuA=1`），形 7 与 f026 `LinkedList::pop`、f102 `MarkSweepGC::mark` **除函数名外逐字节全等** ⇒ **任何发射前静态判据都不能修形 7**。**正向读数（唯一线索）**：`S12H1` 10 事件中 `lfi` 存在的 **7/7 全部 `lfi == m`**（动态回落块与链 IPD 恒等）⇒ 判别性只在**回传侧**；合取 `ovrA=1 ∧ lfi==null`（帧吞不可达块且无回落可回传）在 T1 站点语料面 **0**、唯一命中 = 形 9。**缺口**：`S12H1` 只装 T1 ⇒ T3 站点（形 7 + 24 事件）无回传读数，0 面结论不外推。**还原复验**：clean `timeout 560 zig build` rc=0/63.65s，代次回到 `0e38b018…`/32796 行、`grep -c 'S12'`=0、`probeR11`=0、vs HEAD `+385/−30` 复现；门复跑读数见 §3.16.1 | **⇒ R11 不产生落地批次。** 六轮同层否证闭合（区间/上界 R5 → 归属 R6 → 重联 R7 → terminator+计数 R8/R8.1 → 选路静态字段 R10 → **结构帧界 R11**）⇒ §7 三条路线中 **①（链级双臂选路）与 ②′（只读建表）已被实测排除为充分机制**，唯一与机制同形的落地路线 = **③ 帧收口站点回传**：`last_loop_fallthrough_idx == null` 且链 IPD `m` 存在时，以 `m` 作为回传目标（把动态回落换成静态回落）。**代价与风险（实测波及）**：改动位于 `generateLabelDrivenBlockRange` 的臂尾收口段，若走 `self` 字段传出须为递归做 save/restore（§3.11 同层隐式状态风险）；另须先补 **T3 站点回传探针**（R11 缺口）才能给形 7 定面。**未获老铁点头前不动编译器源码**；待裁决子项：③ 是否开落地批、T3 探针是否补一轮、e) IPD 无函数级缓存、f) 是否推广到 `generateIfFromLabels` 族 |
| ~~**P0**~~ | ~~**R12 静态回落目标（链 IPD）可行性探针轮 = §7 路线 ③ 定面**（R11 自登记强制前置：先补 T3 站点回传探针，才能给形 7/9 定面）~~ | **已完成（2026-10-05，§3.17 + §3.17.1）：路线 ③ 在 T1 侧首次拿到「判据成立 ∧ 语料面 0」**。一枚只读探针 `probeR12Node` + 八处调用（`T1-JOIN`/`T1-NULL`/`T3-PRE`/`T3-POST` × 帧起点/`ei` 两候选），净插入 **`+105/−0`**、stderr-only 无一字进 `writer`；中性双证 = 九形门 `same=7` 逐字同判 + **`S13_SHADOW_DONE total=68 hit_scripts=24 compile_fail=0 drift_ok=68 drift_diff=0`**。**四条实测结论**：① **形 9 命中且只用既有五条件** —— `T1-NULL nk=E` 行 `IPD(ei)=3` 使 `pos=1 ∧ np=3>1 ∧ isLH=0 ∧ iscb=0 ∧ iseb=0 ∧ pro=0` 六项全真，而 `IPD(fs)=6` 被 `np=1`+`pro=1` 双否 ⇒ **候选节点必须是 `ei`**；② **语料面 = 0 事件 / 0 脚本**（6 条语料 `T1-NULL` 读数全部由「位置」单条排除：`m > fs ∧ m ≠ ei`，f067 四行 + f177 两行，见 §3.17.1 原文）⇒ 七轮来第一次「字面照 `lfi_is_join` 写即可落地」；③ **静态 IPD 不是动态回落的一般替代** —— `lfi` 存在的 14 个 `T1-JOIN` 事件仅 **1 条** `IPD==lfi`（f124）⇒ **禁止替换既有动态机制，只允许加 `lfi==null` 兜底支**；④ **T3 侧不落地** —— T3-PRE/T3-POST 两侧合计 **96** 条语料读数五条件真 **0**、`lfi` 覆盖每侧仅 4/48，且红形 7 在该站点 `m=NONE`（链无结构 merge）⇒ 收益 0 而风险不可证 0；**形 7 由「机制前置不成立」排除**（区别于前六轮的「判据不可二分」）。**还原复验**：代次回到 `0e38b018…`/32796 行、`grep -c 'S13R12'`=0、`probeR12Node`=0、vs HEAD `+385/−30`；clean `timeout 560 zig build` rc=0/63.80s；十二道门读数见 §3.17.2 | **⇒ R12 不自行产生落地批次，但把「余 2 形」压缩为「余 1 形（7）」并给出可落地判据。** **待老铁点头的落地项**：在 T1 站点（干净树 `:8871` 所在 `if`）为 `lfi==null` 补 `else if` 兜底支 —— 谓词 = `findChainMergeByPostDom(else_bi)` 存在 ∧ 五条件逐条同 `lfi_is_join`，动作 = `merge_bi = m; processed.remove(m); return_generated = false; break_generated = false;`，**不含任何 PHI 物化**（实测 `nphi=0 ∧ nsrc=0`）。成本 ≈30 min（单站点插入 + 全门复跑），预期 `same=7 → 8 differs=1`（残留 = 形 7）。风险：兜底支只在红形触发（语料面 0），但回传目标是函数级共享 `ret` 块（`tt=r`）⇒ 收口后须复跑硬零漂移门实证。**上一行（余 2 形 + 遗留四项）的 a)/b) 两项已被本行取代**：b) 形 9 的阻塞解除（改判据为「`lfi==null` 兜底」而非「C 站点区间」），a) 形 7 转为「需新机制」的独立命题；c) d) 两项已由 R10 闭环，e) f) 仍待裁决。**未获点头前不动编译器源码** |
| ~~**P0**~~ | ~~**路线 ③ T1 兜底支落地批**（R12 §3.17.1 判据：`lfi==null` 时以 `findChainMergeByPostDom(else_bi)` 为满足五条件的回传目标）~~ | **已按老铁授权落地并实测，随后撤销（2026-10-05，§3.18）= 第八次否证**：代次 `602d809b…`/32817、`+21/−0` 纯插入，`timeout 560 zig build` rc=0。插桩取证（`4208c39a…`/32831，stderr-only）实测 **判据触发面完全正确** —— 形 9 `enter ei=2 blk=4 fs=0 end=9` → `m=3 pos=1 np=3 isLH=0 iscb=0 iseb=0 pro=0 join=1` → `FIRED merge_bi=3`，其余 8 形 0 触发（与 R12 的「红 1 / 绿 0 / 语料 0」逐字吻合）；**但动作惰性**：形 9 的 `main.zig` 与提交代次仅差 1 行注释（`:419`），AOT stdout 逐字不变，九形门仍 `same=7 differs=2` ⇒ **预测 `same=8 differs=1` 否证**。**根因 = 时序**：`then_end` 在行走前定（`:8837–:8854` ⇒ 形 9 取 `end_idx=9`，兄弟臂 5..8 已在帧内发射），`lfi` 只在行走后可知 ⇒ 以 `lfi==null` 为前置的事后 `merge_bi` 交还**原理上**不能撤回已发射臂体 | **⇒ 路线 ③ 的「T1 消费点变体」出局（不是判据错，是消费点选错）。** 已撤销并复验：`src/aot/native_linker.zig` 回到 HEAD `497edc6` 代次（md5 `0e38b018…`、`git status` 干净），撤销后 `zig build` rc=0，九形门复跑 `total=9 same=7 differs=2` 两条红点签名逐字等于 §3.17.2 G1 ⇒ **未留下无功能效应的代码**。**唯一剩余路线**：③ 的**完整形态** = `generateLabelDrivenBlockRange` 增「帧停止块」返回值并把收口目标在**行走前**回传调用层（实测波及调用站点 **94 处**；用 `self` 字段传出须为递归 save/restore ⇒ §3.11 隐式状态风险），或形 7/9 的**新机制**（臂守卫坍缩本体，§3.10）。**禁止**再把任何「行走后消费点」的改判当作形 9 的修法。e) IPD 无函数级缓存、f) 是否推广到 `generateIfFromLabels` 族 —— **仍待裁决** |
| **P0（待老铁裁决）** | **§4.7 成对候选：for 侧「exit 块一跳回落目标」记录 + `for_cond_` 分支帧内停走**（R14 第九次否证的正面产物，R15 单形预探针已实测形 9 几何 `ei=6 tk=0 hop=3 hoplt=1 nlfi=0`）。九轮以来**第一个不是「新造判据」的候选**：一跳记录在 foreach 侧**已存在**（`:12962–:12972` cleanup `.br` 目标 → `ni`，含 `defer ∧ ni < cond_idx` 抑制），帧内停走在 foreach 派发**已存在**（`:7471–:7477`）⇒ 本候选 = 把两件已验证口径补到 for 侧同几何；下游 `:8865` 消费者已实测可接住同一目标块（R13 读数 `join=1`）⇒ 若语料 `HOPQ=0`，则红面 1 / 绿面 0 / 语料面 0，与 R9-B 落地前口径同级 | 影响面（实文复核后收窄）：改动一 = `generateForFromLabels` 出口判定区**纯记录支**（插在 `:14975`/`:14977` 之间，不改 `processed` 标记、不改发射、不改返回值），改动二 = for 分支 +1 停走 + foreach 分支等值改读共用谓词 `armFallthroughStop`；**while 侧不改**（R14 WHC/WHB 红面 0 读数）；不动 `then_end`、不动 `defer` 置位面 | 成本：估算 +22/−6（含共用 helper，落地后改记实测）；**前置已变更**：原「坑 1 出口块纯转发窄读」经实文复核消解（通用路径 `:14977–:14981` 本已发射出口块指令），新前置 = §3.20 须按 `hlbl` 标签前缀分类，确认坑 3 的 `isLoopHeadLabel` 排除支写法；**落地模板已预写于 §4.7 末（未落地）**；验收目标 `same=8 differs=1`（形 9 转绿，形 7 仍红）+ 十二腿门链。**〔2026-10-06 §3.22 复验（#86，零插桩）〕** 锚点与模板标识符**全部等值** ⇒ 点头即可逐字实现；同时三条口径入表：坑 3 的排除面**不得收窄为派发支自用五枚**（§3.22.2 ①）、改动二覆盖面 = 九枚派发返回点中的 `:7483` 一枚且八处弃返回值站点风险由 §3.20 语料面 0 封闭（§3.22.2 ②）；**⛔ 点头前置正式变更** = 先裁决 §3.22.3 的窄化口径 **N1（`lfi ≠ 派发返回值`，推荐：不改字段语义、排除集与放行集构造上不相交）** 或 **N2（新增新鲜度标记）**，因现稿谓词会重触发 R14 实测的 `f124` 停走 = 真实漂移，该批会挂在自家 `diff=0` 硬零漂移门上（成本 = 一整个十二腿编译窗口）。 |
| P1 | 是否把 9 形并入官方回归（现为独立门） | 防复发；并入后本族红形会立刻把官方 68 变红，需与修复批次同批落地 | 门脚本已有，并入需改 harness |
| P2 | 语料增补本族形状（含 3.5.2 的窄/宽两形与 3.5.4 的双臂形） | 需重冻结基线（既有裁决项） | 高 |
