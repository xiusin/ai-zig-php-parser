# AOT-CODEGEN-010 · PHP 关键字大小写不敏感支持缺失：非全小写拼写在 lexer 层坍成标识符 ⇒ 同一关键字按下游文法位置分裂出**五种不同结局**（静默空输出／运行致命／编译期解析失败／错臂无条件执行／偶然等值【非免疫】）；`keyword_lookup.zig` **87 枚表项穷举门**已实测 ⇒ 红面 **59 枚 / 79 形**

**问题 ID**: AOT-CODEGEN-010
**优先级**: **P0**（穷举面实测：静默空输出 **12 形** + 无消息错值 **7 形** 全程 rc=0 ⇒ 假绿；另有 **25 形**使**合法 PHP 语法在 AOT 编译失败**，按宪法 §七-8 前半句禁止以简化脚本绕过）
**性质**: 编译前端（`src/compiler/lexer.zig` + `src/compiler/keyword_lookup.zig`）⇒ **跨模式共享**：AOT 与字节码/解释器模式走同一 `lexIdentifier`；本轮按宪法 §五**只归因不修复**，且已实测两模式的结局同族（见 §2.2）
**状态**: **R-2 批 + §8 七枚缺陷中六枚已修复（2026-10-07）＋ R-3 批（替代语法严格闭合，2026-10-09）＋ R-5 批（`switch` 臂表位严格化 = §7-15c 面孔 A，2026-10-09 任务 #127）已落地并全链验收绿，#3 goto 已由 R-125 降级批关闭（2026-10-11，§3.9，门 D8 `defect_red=0`）与面 B/C（待裁决；2026-10-09 任务 #126 由永久侧门 K 取证收口 ⇒ 量化为 4 枚 `OVER_ACCEPT`（面 A，**已由 R-5 收掉**）+ 5 枚 `AOT_ONLY_RED`（面 B）+ `default` 臂位次缺失（面 C），面 B/C 已另立 [AOT-CODEGEN-011](AOT-CODEGEN-011-switch-case-semicolon-terminator-and-default-arm-position.md)，落地仍待 D-1…D-4 裁决），📦 R-3 + R-5 两批**均未提交**（git 实测 `--porcelain` = 14 枚 M（已入库但被本两批改到）+ 16 枚 ??（新建资产），`git diff --numstat HEAD -- src/` = **+81/−6** ⇒ 该 diff 同时含 R-3 的 +64/−6 与 R-5 的 +17/−0，**提交消息必须点名两批**；HEAD 现为 `f9432e2`，其祖先 `73f4d6b` 已把 R-2 代次门资产入库 ⇒ M 项≠未入库资产，勿混判）**：R-2/R-2b/R-4 + 名位容忍支（已由老铁 `b92f206` 入库）＋ §8 #1/#2/#5（R123）＋ §8 #4/#6/#7（R124，调用解析序 + iterable + 消息渲染）全部落地并验收 —— 终态实测：门 H **face=0**（79 形全绿，原 59 红）+ **inverse_face=0**（反例组 21 形全绿，原 15 红）+ **confounded=1**（余 k_goto=#3）+ probe_compile_fail=0；门 E/F/G 全绿且守卫臂零越界；门 H2 **`over_accept` 14→12**（R-3 批把关闭标记位 2 枚收为同拒，其余 12 枚仍待裁决，见 §3.6）；门 I `aot_same=19` 且 tree/bc 读数逐项不变（D-2 分叉达成）；影子 68 语料 `main.zig` md5 **68/68 一致**；主回归 **Pass 67 / Skip 1** 保持。**R-3 批（门 J P1）验收 = 门 J v3 29 形 `same=19 over_accept=0 both_reject=10 aot_only_red=0 run_red=0` + 本代次实测过的九腿全绿（门 E/F/G/H/H2/I/D8 + 影子门 + 官方主回归，逐腿读数见 §3.6「R-3 批落地实测」），链耗时实测 56m33s。R-5 批（面孔 A）验收 = 门 K `over_accept` 4→0 且硬守卫列 `aot_only_red` 恒 5／`diff_php_ok` 恒 1（面 B/C 零扰动）+ 新建永久侧门 L 23 形 `same=10 over_accept=0 aot_only_red=0`（并把 R-3 漏网形 `l_alt_semi_arm` 一并收掉）+ 其余八腿（J/D8/E/F/G/H/H2/I）与影子逐行 `diff_rows=0` + 主回归 Pass 67/Skip 1，十腿读数见 §3.8 与 §6「R-5 批落地后实测读数」，链耗时实测 56m24s**（R-2 代二进制 `b416d3fbceed199b186676619043bcc5`｜R-3 代二进制 `81f8a55a989f9a793fec2f75c32fd37d`｜R-5 代二进制 `6939cd2e891f20aef590de2585b15681`｜**R-125 goto 降级代二进制 `5c436e9e48e816e666c8996f29d18138`（含 R-3/R-5 合并态），链 V 验收 = 门 D8 `defect_red=0 guard_same=14` + 门 H `face=0 noface=79 confounded=0 inverse_face=0`（k_goto 的 CONFOUNDED 亦清零）+ 影子 68/68 + 主回归 Pass 67/Skip 1，读数见 §3.9**｜**R-126 配对下沉代二进制 `85b51931d0f5b79f2d681e1481a1ff3e`，链 VI 同口径全绿（函数体/块内 goto 循环解除登记，f1/f2/f3 探针全绿），读数见 §3.9**）
**发现日期**: 2026-10-07（任务 #117 收窄「解释器模式 `var_export(静态属性)` panic」时顺带实测；非 AOT-RUNTIME-002 家族，故另立本单）
**触发档**: 默认档（`--compile --no-debug-info`），无需抬档

**代次锚点（本轮实测，非记忆）**

| 资产 | md5 | 行数 |
|---|---|---|
| `zig-out/bin/php-interpreter` | `1f15e4ce9b5c9cdaaef7cabf5efb9c76` | — |
| `src/compiler/lexer.zig` | `21f02e926ee28c7354aa92507136074d` | 530 |
| `src/compiler/keyword_lookup.zig` | `b8832bef829d3e0c11c4e249700bfddd` | 118（关键字条目 87 枚，`grep -c '^    \.{ '` 实测） |
| `src/compiler/parser.zig` | `5995c1e75c55a2c5581e875406113f14` | 4131（任务 #119 代次刷新） |
| `src/aot/runtime_lib_template.zig` | `008b7b639f1069cb73e443064e115ed1` | —（E 类常量表锚点所在） |
| `fuzzy_scripts_720/tmp/c010_keyword_case_gate_tmp.sh`（永久侧门 E，任务 #118 新立） | `1367584f9b0a3a64dc2e9181ef81c77f` | 109 |
| `fuzzy_scripts_720/tmp/c010_keyword_case_tmp.tsv`（侧门 E 读数） | 门尾行 `C010KW_DONE shapes=19 same=8 diff=8 silent_empty=3 aot_fatal=3 compile_fail=3` | `ELAPSED=60s`（= 3.2 s/形） |
| `fuzzy_scripts_720/tmp/c010_mechanism_gate_tmp.sh`（**永久侧门 F = R-1 归因门**，任务 #119 新立） | `d71380842e667ad3fdafb0db02ec6e69` | 149 |
| `fuzzy_scripts_720/tmp/c010_mechanism_tmp.tsv`（侧门 F 读数） | 门尾行 `C010MECH_DONE shapes=8 same=4 diff=4 zero_instr=1 compile_fail=0` | `ELAPSED=30s`（= 3.75 s/形） |
| `fuzzy_scripts_720/tmp/c010_constant_case_gate_tmp.sh`（**永久侧门 G = R-2b 常量表拼写面**，任务 #119 新立） | `921244072b7e2482d4da83c907b6566c` | 103 |
| `fuzzy_scripts_720/tmp/c010_constant_case_tmp.tsv`（侧门 G 读数） | 门尾行 `C010G_DONE shapes=7 same=4 diff=3 red_confirmed=3 guard_same=4 guard_red=0 compile_fail=0` | `ELAPSED=26s`（= 3.7 s/形） |
| `fuzzy_scripts_720/tmp/c010_kw_full_table_gate_tmp.sh`（**永久侧门 H = §7-2 的 87 枚表项穷举双臂门**，任务 #120 新立；修门两轮：① `k_callable` 坏探针 + `php -l` 预检与 `BAD_PROBE_*` 两类，② 反例组由 7 形扩为 **7 词 × 3 名位 = 21 形**） | `c5d6343151193a7e489f814f309ae39c` | 279 |
| `fuzzy_scripts_720/tmp/c010_kw_full_table_tmp.tsv`（侧门 H 读数，**注册读数 = 两轮修门后的全量跑**，107 行 = 4 表头 + 79 主群 + 21 反例组 + 2 门尾） | 门尾行 `C010H_DONE shapes=79 arms=200 face=59 noface=15 confounded=5 bad_probe=0 ctrl_compile_fail=1 probe_compile_fail=25 probe_timeout=0 inverse_shapes=21 inverse_face=15 inverse_noface=6 inverse_confounded=0 repo_build_residue=0 SMOKE_ONLY=0` | `ELAPSED=595s`（= 6.0 s/形，共 100 形、每形两次 AOT 编译）<br>⇒ 主群 79 行与上一轮（`ELAPSED=527s` 那次，仅反例组形集不同）逐字节比对 `run1_rows=79 run2_rows=79 diff_bytes=0` ⇒ 自证「修门只动了反例组」 |
| `fuzzy_scripts_720/tmp/c010_noface_tolerance_gate_tmp.sh`（**永久侧门 H2 = 15 枚 NOFACE 的同位换瞎词判别门**，任务 #120 新立；★ **任务 #125 已于 2026-10-09 修门**：补 `BOTH_REJECT`/`AOT_ONLY_RED` 分桶 + `parser_md5` 锚点 + `aot_log=` 列 ⇒ 本行为 R-2 前初代，当代次脚本 md5 `582ca74d50ff85567ac933b0f85dc7b3`／116 行，见 §3.5.1） | `8e11de20dd598f0875d166022f4c905c` | 99 |
| `fuzzy_scripts_720/tmp/c010_noface_tolerance_tmp.tsv`（侧门 H2 读数；★ 初代四桶口径，当代次读数见 §3.5.1） | 门尾行 `C010H2_DONE shapes=15 over_accept=14 strict_same=1 aot_compile_fail=0 php_ok_aot_diff=0 repo_build_residue=0 SMOKE_ONLY=0` | `ELAPSED=54s`（= 3.6 s/形） |
| `fuzzy_scripts_720/tmp/c010_crossmode_gate_tmp.sh`（**永久侧门 I = 跨模式 AOT/tree/bytecode 对照门，§7-4 量化前置**，任务 #120 新立，源形逐字复制门 E 的 19 形；修门 = `ONLY=` 补循环级过滤） | `d28ae3dcaa57afe4b70829cf827967d1` | 138 |
| `fuzzy_scripts_720/tmp/c010_crossmode_tmp.tsv`（侧门 I 读数） | 门尾行 `C010I_DONE shapes=19 tree_same=7 tree_diff=12 bc_same=7 bc_diff=12 aot_same=8 aot_diff=8 aot_compile_fail=3 both_red=11 vm_only_red=1 aot_only_red=0 repo_build_residue=0 SMOKE_ONLY=0` | `ELAPSED=57s`（= 3.0 s/形，每形一次 AOT 编译 + 两次 VM 执行） |

**R-2 批落地后代次锚点（2026-10-07 实测；前表为修复前冻结代次，本表为落地球）**

| 资产 | md5 | 说明 |
|---|---|---|
| `zig-out/bin/php-interpreter`（落地下） | `a71d97d7bef21bbcc853424cd320498f` | 修复前冻结二进制 `1f15e4ce…` 已备份 `/tmp/c010_prefix_backup/` |
| `src/compiler/keyword_lookup.zig` | `ef70993a7caac6deb9b2e5a23bf7d143` | 186 行：87 枚键抽出为 `raw_entries` 单一事实源 + `max_key_len`（R-4）+ `lookupIgnoreCase`（R-2）+ 4 枚单测（含 87 键 × 3 拼写穷举） |
| `src/compiler/lexer.zig` | `e3dd4191a1c3dfdf816b5873b4c60e5f` | `case_insensitive_keywords` 旗标字段 + `lexIdentifier` 双路（旗标关 = 原路径逐字节） |
| `src/compiler/parser.zig` | `14ac64ca90d1d95a46ace93f10b4c4e2` | 4208 行：`initWithModeInsensitive` + `isToleratedNameTag`/`eatNameIdentifier` + `isAotExtendedKeywordIdentifierTag`（6 枚）+ 15 处名位容忍支 + instanceof/类型位扩展 + `parsePrimaryType` 规范小写 intern |
| `src/main.zig` | `34a492786c7dbacf9522c99631730219` | AOT 入口置旗标 + 多文件检测折形（第四面孔 ①） |
| `src/aot/multi_file_compiler.zig` | `3e9952ad7aadd91c44c01416bf3c70d7` | 多文件 AOT 路径置旗标 |
| `src/aot/runtime_lib_template.zig` | `6e906d61563845a01e8ddc5cbffd89b5` | `php_constant_get` 仅 true/false/null 三枚关键字常量名忽略大小写（R-2b） |
| `src/aot/dependency_resolver.zig` | `77fbe87dbe89a7618afa2fb4aa576554` | `matchKeyword` 折形（第四面孔 ②） |
| `fuzzy_scripts_720/tmp/c010_shadow_main_md5_tmp.sh` | `7cd0b611c3787ddaa121f78d97237afb` | 影子门：68 语料 × 新旧二进制 `main.zig` md5 对照 |
| `fuzzy_scripts_720/tmp/c010_shadow_main_md5_tmp.tsv` | `ef7fac035855e3b0f3d0d326a0be4b1b` | `C010_SHADOW_DONE total=68 same=68 diff=0 miss=0`（末行汇总为超时后手工补记，136 行数据完整） |
| `fuzzy_scripts_720/tmp/c010_acceptance_chain_tmp.sh` | `d12e2fa96016a065c5f5da86253106b5` | 验收链（影子 → 六门 → 主回归，串行） |

> **⚠ 代次已过三轮（2026-10-09 实测重登）**：上表二进制 `a71d97d7…` 为 **R-2 落地代**，非当前树。
> **R-3 批**（替代语法严格闭合）代次锚点 = `parser.zig` `5ad452fe…` / 二进制 `81f8a55a…`，读数登记在 §3.6「R-3 批落地实测」；
> **R-5 批**（`switch` 臂表位严格化 = 面孔 A）当代次锚点 = `parser.zig` `1eab26c068b13b9f904d2f432464d852`／**4305 行** / 二进制 `6939cd2e891f20aef590de2585b15681`，`lexer.zig` `e3dd4191…`（543 行）与 `keyword_lookup.zig` `ef70993a…`（186 行）**逐字未动** ⇒ 本批零词法面扰动，读数登记在 §3.8 与 §6「R-5 批落地后实测读数」。
> **两批都还在未提交的工作树里**（实测 `git show HEAD:src/compiler/parser.zig | md5 -q` = `e3987a361d1db45bc3eadefc7afa249e`／4230 行 ⇒ HEAD 只到 §8 缺陷修复代）⇒ 算术自证：4230 + (R-3 `+64/−6`) + (R-5 `+17/−0`) = **4305** = 当前树行数，与 `git diff --numstat HEAD -- src/` 的 `+81/−6` 一致。
> 引用任何门的读数前先按 §9 的三级判代次顺序核对表头 `compiler_md5=`；**★ 新增口径（§9.7）**：`git show <commit>:<path> | md5 -q` 这条「已入库等价取证」捷径只对**已提交**代次成立，R-3/R-5 未入库 ⇒ 判代次只能取门 TSV 表头 + 工作树 md5。

---

## 1. 测法与判读口径

- 一形一文件、纯直线语句、逐形独立编译；类名/函数名逐形专属（进程级全局注册表）。
- 每形**只输出自身标记**（不加统一 `DONE` 行）⇒ `silent_empty` 判据 = AOT 侧输出为**空文件**而 PHP 侧非空。
- 每组配同语义的**全小写控制臂**（`*_ctl`，共 7 枚，实测**全部 SAME**）⇒ 八枚红形不可归因于门坏掉。
- 等值 = 归一化合并 stdout+stderr 逐字节；exit 码只记录不判等。
- **固化坑 ①**：`--compile` 遇 `Parse error` 时**退出码仍为 0 且不产出二进制** ⇒ 编译失败判据必须取「产物不可执行」，不能取 `compile_rc`（首轮即因取 rc 而把三形误判为可运行）。
- **固化坑 ②**（大写 `ELSE`）：必须用**真条件**形 ⇒ 实测 AOT 把 `ELSE {…}` 的块**无条件执行**；若条件为假，PHP 也只走 else 块 ⇒ 两侧输出偶然逐字节相同（零区分度）。首轮用假条件得 `same=9`，改真条件后 `same=8`，本单只引用**修正后**的 19 形读数。

---

## 2. 实测：19 形逐形结局

### 2.1 AOT（侧门 E，`C010KW_DONE shapes=19 same=8 diff=8 silent_empty=3 aot_fatal=3 compile_fail=3`）

| 形 | 关键字拼写 | PHP 8.5.8 | AOT 实测 | 结局类别 |
|---|---|---|---|---|
| `kw_echo_ctl`（控制臂） | `echo` 多参 | `e=1` | `e=1` | **SAME** |
| `kw_echo_title` | `Echo` | `e=1` | **空输出** rc=0 | **静默空输出** |
| `kw_echo_upper` | `ECHO` | `e=1` | **空输出** rc=0 | **静默空输出** |
| `kw_print_ctl`（控制臂） | `print` | `p=1` | `p=1` | **SAME** |
| `kw_print_title` | `Print` | `p=1` | **空输出** rc=0 | **静默空输出** |
| `kw_if_ctl`（控制臂） | `if`/`else` | `i=gt` | `i=gt` | **SAME** |
| `kw_if_title` | `If (…)` | `i=gt` | — | **编译期解析失败**（`Parse error: Unexpected token in expression on line 3`） |
| `kw_else_upper` | `ELSE`（真条件） | `i=gt` | `i=gt` **且多打** `i=le` rc=0 | **静默错臂**（else 块无条件执行 ⇒ 双输出） |
| `kw_return_ctl`（控制臂） | `return` | `r=3` | `r=3` | **SAME** |
| `kw_return_upper` | `RETURN` | `r=3` | `r=`（**空值**）rc=0 | **静默错值**（返回语句丢失） |
| `kw_function_ctl`（控制臂） | `function` | `m=6` | `m=6` | **SAME** |
| `kw_function_upper` | `FUNCTION` | `m=6` | `Warning: Undefined variable $a` + `Fatal … Call to undefined function fc4()` rc=255 | **运行致命**（函数未注册） |
| `kw_class_new_ctl`（控制臂） | `class`/`new` | `c=3` | `c=3` | **SAME** |
| `kw_class_upper` | `CLASS` | `c=3` | `Fatal … Class "CC6" not found` rc=255 | **运行致命**（类未注册） |
| `kw_new_upper` | `NEW` | `c=3` | — | **编译期解析失败**（`syntax error, unexpected identifier, expecting ";" on line 3`） |
| `kw_foreach_ctl`（控制臂） | `foreach` | `f=1` `f=2` | 同 | **SAME** |
| `kw_foreach_upper` | `FOREACH` | `f=1` `f=2` | — | **编译期解析失败**（`Unexpected token in expression on line 2`） |
| `kw_while_upper` | `WHILE` | `w=0` `w=1` | `Fatal … Call to undefined function WHILE()` rc=255 | **运行致命**（被当函数调用） |
| `kw_bool_upper` | `TRUE`/`FALSE`/`NULL` | `b=truefalseNULL` | 同 | **SAME ⇒ 偶然等值（非免疫）**，成因已归因（见 §3.1 E 类） |

⇒ 同一个根（关键字查不中）按**下游文法位置**分裂为五种结局：语句关键字（`echo`/`print`/`return`）⇒ **静默**；声明关键字（`function`/`class`）⇒ 注册表落空 ⇒ **运行致命**；控制结构起始（`if`/`foreach`）⇒ **编译期解析失败**；控制结构中段（`else`）⇒ **错臂双执行**；`new` ⇒ 解析失败；`while` ⇒ 被当函数调用；`TRUE/FALSE/NULL` ⇒ **看似正常，实为两处缺陷互抵消**。逐类到行见 §3.1。

### 2.2 跨模式对照（**永久侧门 I**，门 E 同一批 19 形 × **AOT / tree / bytecode** 三模式实测；任务 #120；按宪法 §五**只测不修**）

> 源形逐字复制侧门 E 的 `body_for`（未回改侧门 E ⇒ 规则 11 未被违反），故本表 AOT 列与 §2.1 可直接对齐。
> 本门口径新增：VM 模式在 stderr 末尾打印 `=== PHP Interpreter Performance Statistics ===` 统计段 ⇒ `norm()` 必须从该行起整段删除，否则**所有** VM 臂恒 DIFF、门失去判别力。

| 形 | PHP 8.5.8 | tree（解释器，默认模式） | bytecode | AOT | 交叉类 |
|---|---|---|---|---|---|
| 七枚 `*_ctl` 控制臂 | 各自真值 | **SAME** | **SAME** | **SAME** | `all_green` |
| `kw_echo_title` | `e=1` | `Uncaught UndefinedVariableError: Undefined variable: $Echo` | 空输出 rc=0 | 空输出 rc=0 | `both_red` |
| `kw_echo_upper` | `e=1` | `Undefined variable: $ECHO` | 空输出 | 空输出 | `both_red` |
| `kw_print_title` | `p=1` | `Undefined variable: $Print` | 空输出 | 空输出 | `both_red` |
| `kw_if_title` | `i=gt` | `Call to undefined function If()` | `Call to undefined function If()` | **编译期 `Parse error`** | `both_red` |
| `kw_else_upper` | `i=gt` | `i=gt` + `Undefined variable: $ELSE` | `i=gt` + `i=le`（错臂双打） | `i=gt` + `i=le`（错臂双打） | `both_red` |
| `kw_return_upper` | `r=3` | `r=` + `Undefined variable: $RETURN` | `r=`（空值） | `r=`（空值） | `both_red` |
| `kw_function_upper` | `m=6` | `Undefined variable: $FUNCTION` | `Undefined variable: $FUNCTION` | `Warning: $a` + `Fatal: Call to undefined function fc4()` | `both_red` |
| `kw_class_upper` | `c=3` | `Undefined variable: $CLASS` | `c=`（空值） | `Fatal: Class "CC6" not found` | `both_red` |
| `kw_new_upper` | `c=3` | `c=` + `Undefined variable: $o` | `c=`（空值） | **编译期 `syntax error, unexpected identifier, expecting ";"`** | `both_red` |
| `kw_foreach_upper` | `f=1` `f=2` | 空输出 | 空输出 | **编译期 `Unexpected token in expression`** | `both_red` |
| `kw_while_upper` | `w=0` `w=1` | `Call to undefined function WHILE()` | `Call to undefined function WHILE()` | `Fatal: Call to undefined function WHILE()` | `both_red` |
| `kw_bool_upper` | `b=truefalseNULL` | `Undefined variable: $TRUE` | `b=NULLNULLNULL` | **SAME**（偶然等值） | **`vm_only_red`** |

**总数（实测）**：`C010I_DONE shapes=19 tree_same=7 tree_diff=12 bc_same=7 bc_diff=12 aot_same=8 aot_diff=8 aot_compile_fail=3 both_red=11 vm_only_red=1 aot_only_red=0 repo_build_residue=0`，`ELAPSED=57s`（= **3.0 s/形**，每形含三模式 + PHP 真值共 4 次执行）。
**跨 run 自证**：修 `ONLY` 通道前的首跑（因缺陷把全量写进 smoke 文件）与注册全量跑的总数行**逐字符相同** ⇒ 本门读数跨 run 稳定；smoke 文件已删。

⇒ **对宪法 §五 裁决的直接约束（实测，非推断）**：
1. **`aot_only_red = 0`** ⇒ 12 枚红形里**没有任何一枚**只在 AOT 红 ⇒ 「只修 AOT」在本族**一朵都关不掉**；本单的根在**三模式共享的编译前端**，R-2 一旦落在 `keyword_lookup`/`lexer`，tree 与 bytecode 模式**必然同修**，不存在「只改 AOT 一侧」的落点（除非分叉前端，禁）。⇒ 需老铁明示的不是「要不要顺带修」，而是「**接受 R-2 天然三模式同修**」。
2. 模式差异只发生在**下游**：三枚 `COMPILE_FAIL` 形（`If`/`NEW`/`FOREACH`）在 VM 模式下**能跑但错值/致命**，只有 AOT 在编译期拒绝 ⇒ 与 §3.1 C 类「语句层臂表缺项」同源，不新增修复面。
3. **`kw_bool_upper` 是唯一 `vm_only_red`** ⇒ §3.1 E 类那处「偶然等值」**只在 AOT 成立**（VM 两模式各以另一种方式落空）⇒ 冻结基线对该面在 VM 模式**无保护**，且不可把 AOT 的 SAME 当成本族已支持的证据。

> 原 4 形定性表（任务 #117/#118）已被本表**整体取代**；其中一处措辞据实测更正：`Echo "e=1"` 在解释器模式并非「空输出（仅打统计段）」，而是 `Uncaught UndefinedVariableError: Undefined variable: $Echo`（坍成的裸名被当**变量**而非语句）。

---

## 3. 机制锚点（实文核对，只读）

| 锚点 | 实文 | 结论 |
|---|---|---|
| `src/compiler/lexer.zig:384 lexIdentifier` | `:386` 取 `const text = self.buffer[start..self.pos];`（**原始文本，未归一化大小写**）⇒ `:390` `text.len <= 5` 走 `lookupFast`，`:394` `text.len <= 15` 走 `lookup`，否则不查 | 关键字识别**唯一**入口，无大小写归一化支路 |
| `src/compiler/keyword_lookup.zig:6` | `const keyword_map = std.StaticStringMap(Token.Tag).initComptime(…)`，**87 枚条目实测为两种拼写规范混用**：80 枚**全小写**关键字 + **7 枚全大写魔术常量**（`:81-87` 的 `__DIR__`/`__FILE__`/`__LINE__`/`__CLASS__`/`__METHOD__`/`__FUNCTION__`/`__NAMESPACE__`） | `StaticStringMap.get` 为大小写敏感 ⇒ `Echo`/`ECHO`/`IF`/`RETURN`… 一律查不中；且**表自身规范不统一** ⇒ 归一化方向必须「原文与表键同折一端」，若只把原文折成**小写**再查表，则魔术常量组反而**丢**命中（§3.4.5 判据 5） |
| `:99 lookup` / `:104 lookupFast` | 均为 `return keyword_map.get(text);`，无 `eqlIgnoreCase`、无 lowercase 副本 | 查不中即返回 `null` |
| `src/compiler/lexer.zig:400-402` | 非关键词 ⇒ `t_string`（Go 模式则 `t_go_identifier`） | **坍成标识符** ⇒ 后续按文法位置分别变成「裸常量表达式」「函数调用」「未知 token」 |
| 全仓 `eqlIgnoreCase` 先例 | `grep -rn eqlIgnoreCase src/compiler/*.zig` ⇒ **0 命中**（`lexer.zig`/`parser.zig`/`keyword_lookup.zig` 各 0） | 修此面需在编译前端**引入新惯用法**（无现成先例可抄），故必须先做归因轮再谈落地 |
| 长度门槛 | `:390`/`:394` 仅查 `len <= 15` | **本代次实测更正**：表内 87 枚键的最长键为 `__NAMESPACE__`（**13** 字符），其余 ≥10 字符者为 `implements`/`instanceof`/`endforeach`/`__METHOD__`(10)、`__FUNCTION__`/`include_once`/`require_once`(12) ⇒ 距上限**仅剩 2 字符余量**（旧措辞「最长 `endswitch`(9)」经 `grep -oE '^\s*\.\s*\{\s*"'` 实测为错，已更正）。该上限仍是宪法 §四-3 的硬编码违反：新增 ≥16 字符键会**静默不查表**（登记于 §7） |

**R-1 归因轮已闭环（任务 #119，永久侧门 F 8 形实测 + 生成码结构实读）**：原先的「未取证项」= 「lexer 交出 `t_string` 之后的下游断点未逐形取行」，现已逐类到行，见 §3.1。

### 3.1 五类下游断点（同一 lexer 根 × 五种文法位 ⇒ 逐类到行）

| 类 | 侧门 F 形 | 断点链（行锚点，均为本代次实文核对） | 发射面实测（`instr` = 本形源文件的 `setSourceLocation` 次数） |
|---|---|---|---|
| **A 静默空输出（rc=0）** | `m_echo_bare_title`（`Echo "A\n";`） | ① `lexer.zig:386` 原文切片 → `keyword_lookup.zig:99/:104` `keyword_map.get` 查不中 → ② `lexer.zig:400-402` 落 `t_string` → ③ `parser.zig:480-486`（`.t_string` 且 peek 非 colon）⇒ `parseExpressionStatement()`（`:2408`）→ ④ **`:2410` 软分号** `if (self.curr.tag == .semicolon) self.nextToken();` ⇒ **缺 `;` 不报错**，同行剩余 token 被**重新切成独立语句** → ⑤ `parser.zig:3044-3061`（`:3059 resolveName`）把裸标识符接成 `.variable` 节点 ⇒ 顶层纯变量/字面量语句无副作用 ⇒ **IR 侧整句消失** | **`instr=0`、`echo=0`**（PHP 侧输出 `A`，AOT 侧空文件 rc=0）⇒ 本门唯一 `zero_instr` 计数。同机制探针生成码 `__main__` 体只剩 `return runtime.Value.initNull();`，且字符串字面量**连 `static_strings` 表项都没有** ⇒ 「静默」发生在 parse/IR 层，**不是运行期把 echo 吞掉** |
| **B 运行致命（rc=255）** | `m_echo_paren_title`（`Echo ("A\n");`） | ①②同 A → ③ `parser.zig:2785 parseUnaryPostfix` 的 **`:2791 if (tag == .l_paren)`** ⇒ 生成**函数调用**节点（`:2792` 注释即此支）→ ④ 未注册函数 ⇒ 运行期 `Call to undefined function Echo()` | `instr=3`、**`echo=0`**、`undef=Call to undefined function Echo` ⇒ **A/B 同语义只差一对括号**（`Echo "A\n";` vs `Echo ("A\n");`）⇒ 该判别锁死「静默」来自 A 支零指令而非 B 支 |
| **C 编译期解析失败（`--compile` rc=0 且无产物）** | 侧门 E 的 `kw_if_title`/`kw_foreach_upper`/`kw_new_upper` | 大写头被接成 call 后，其后的 `else`/`as` 落到语句层 `parser.zig:496 else => parseExpressionStatement` ⇒ `parseUnary`（`:2747`）臂表无对应 token ⇒ `Unexpected token in expression`；子支 C2（`$o = NEW C();`）= **赋值右侧要求分号** ⇒ `unexpected identifier, expecting ";"` | **生成码侧无读数**：侧门 F 的 8 形全为可编译形 ⇒ C 类证据 = 侧门 E 的 `compile.log` 错误文本 + parser 实文核对（未取 AST 侧行级读数）。与 A 的软分号形成对照 ⇒ **同一份文法在语句位软（`:2410` 是唯一放宽点）、在赋值位硬** |
| **D 臂无条件执行（rc=0 多打一行）** | `m_else_upper`（`if (…) {echo "P";} ELSE {echo "Q";}`） | `parseIf` 只匹配 `.k_else` token ⇒ then 臂后链**正常闭合**；`ELSE` 走 A 支成零指令语句；紧随的 `{…}` 由 **`parser.zig:473 .l_brace => parseBlock`** 接成**独立块语句** | 生成码结构实读（`/private/tmp/c010d1.*/main.zig`）：`:69 if (reg_3.toBool()) {` → then 臂 `_ = try runtime.php_echo(reg_4);` 在 **`:76`（守卫内）** → 守卫闭合 **`:86`** → else 串 `static_strings[3]` 的 `php_echo(reg_6)` 在 **`:93`（顶层）** ⇒ 逐字节**在 if 之外**。**计数与对照臂逐位相同**（`instr=9`、`echo=2` 两形皆然）⇒ D 类是**落点缺陷而非发射量缺陷** ⇒ R-3 的「零指令金丝雀」抓不到 D 类 |
| **E 偶然等值（非免疫）** | `m_true_upper`（`$t2 = TRUE;`）**SAME** / `m_true_title`（`$t3 = True;`）**DIFF** | 大写 `TRUE` 同样失配 → `.variable "TRUE"` → 发射 `getGlobalVar("TRUE")`（F 门 `gvar` 列实测字面量）→ 生成码 `getGlobalVar`（`main.zig:1043`）**先查** `runtime.constants.get(name)`（`:1066-1070`）→ 命中内置常量表，而该表**键只有大写一种拼写**：`runtime_lib_template.zig:7614 .{ .name = "TRUE", .value = true }`、`:7615 "FALSE"`、`:7637 dupe(u8, "NULL")`。小写 `true` 走**另一条路**：`keyword_lookup.zig:25/26/42` → lexer `k_true/k_false/k_null` → `parser.zig:2972-2982` 的 `literal_bool`/`literal_null` 节点 ⇒ 不经常量表 | `m_true_upper`：`instr=10 echo=3 gvar=getGlobalVar("TRUE")` ⇒ **SAME 但对错路**（两侧结果恰好一致）。`m_true_title`：`gvar=getGlobalVar("True")` ⇒ `PHP Warning: Undefined variable True` + `t=NULL`，PHP 侧 `t=true` ⇒ **预测（键只有大写 ⇒ Title 形必落空）实测成立**，且 `kw_bool_upper` 的 SAME 由「未取证」改判为**两处独立缺陷互抵消**（词法大小写敏感 × 常量表单拼写键） |

⇒ **对修复路线的直接约束（实测）**：E 类证明本族存在**第二张拼写敏感面**（运行期常量表按单拼写键索引）。该面**不经 lexer 缺陷即可达**：`constant("true")` / `constant("false")` / `constant("Null")` 三枚探针源码内**没有任何大写关键字拼写**，AOT 侧仍全部 `Fatal: Undefined constant`（PHP 8.5.8 侧 `true`/`false`/`NULL`）⇒ **R-2 单落地对该面零收敛**，必须并批 R-2b；反之非关键字常量与用户常量两侧语义已等值（PHP 自身对 `constant("php_int_max")`、`constant("myc")` 也 Fatal）⇒ **禁止把常量表改成全局忽略大小写**，那会把已等值的面改成回归。逐形读数见 §5 R-2b。

### 3.2 侧门 F 的两处固化坑（首跑踩到，修正后才引用总数）

1. **KEEP_TEMP 目录必须在抽取生成码之后再删**：首跑把清理循环放在选取 `GEN` 之后、`grep` 之前 ⇒ 8 形 `instr`/`echo` 列**恒为 0**（含三枚控制臂，而它们可证发射 `php_echo`）。修正为 `cleanup_gen` 函数、在抽取后与 `COMPILE_FAIL` 早退支各调一次。
2. **`setSourceLocation` 嵌的是 realpath**：macOS 下 `mktemp -d /tmp/…` 返回 `/tmp/…` 而生成码写 `/private/tmp/…` ⇒ 直接拿 `$SRC` 去 grep 恒 0 命中；修正为 `RSRC="$(cd "$T" && pwd -P)/…"`。
⇒ 首跑的 `zero_instr=8` 总数**禁止引用**；本单只登记修正后读数的 `C010MECH_DONE shapes=8 same=4 diff=4 zero_instr=1 compile_fail=0`（`ELAPSED=30s`）。

### 3.3 R-2b 面：内置常量表拼写键（永久侧门 G，7 形实测 `shapes=7 same=4 diff=3 red_confirmed=3 guard_same=4 guard_red=0 compile_fail=0`）

**本组探针源码内没有任何大写关键字拼写** ⇒ 与 §3 的 lexer 根**无关**，是一张独立面孔（走 `constant("<名字>")` 动态查名入口）。

| 形 | 探针 | PHP 8.5.8 | AOT 实测 | 角色 | 判读 |
|---|---|---|---|---|---|
| `k_const_true_lower` | `constant("true")` | `a=true` | `a=` + `Fatal: Undefined constant "true"` rc=255 | red_expected | **DIFF（红）** |
| `k_const_false_lower` | `constant("false")` | `b=false` | `b=` + `Fatal: Undefined constant "false"` rc=255 | red_expected | **DIFF（红）** |
| `k_const_null_title` | `constant("Null")` | `c=NULL` | `c=` + `Fatal: Undefined constant "Null"` rc=255 | red_expected | **DIFF（红）** |
| `k_const_true_upper` | `constant("TRUE")` | `d=true` | `d=true` | guard_same | SAME（现状唯一可用拼写） |
| `k_const_nonkw_lower` | `constant("php_int_max")` | `e=` + Fatal rc=255 | `e=` + Fatal rc=255 | guard_same | **两侧等值 ⇒ 非关键字内置常量本就该敏感** |
| `k_const_user_exact` | `define("GgC1",7)` + `constant("GgC1")` | `f=7` | `f=7` | guard_same | SAME |
| `k_const_user_wrong` | `define("GgC2",8)` + `constant("ggc2")` | `g=` + Fatal rc=255 | `g=` + Fatal rc=255 | guard_same | **两侧等值 ⇒ 用户常量侧已是 PHP 语义** |

⇒ **修复覆盖面边界（实测给出，禁止扩面）**：红面**仅** `true`/`false`/`null` 三枚关键字常量的动态查名；`php_int_max`/用户常量两枚守卫臂已与 PHP 逐字节等值 ⇒ 若 R-2b 把常量表查名改成**全局**忽略大小写，这两臂会由绿转红（把已等值的面改成回归）⇒ 落地形态必须限定「仅这三枚关键字常量名忽略大小写」。
⇒ 本门口径与侧门 E/F 不同（`norm()` 额外剥离 `PHP ` 前缀、删除 `in 路径:行` 尾巴、折叠双空格），理由与首跑踩到的坑登记在门头；**不回改侧门 E/F**（其总数已登记）。

### 3.4 表项穷举门：79 形双臂实测（**永久侧门 H = §7-2 的穷举门**，任务 #120 新立）

**形集推导（实测口径，非估算）**：`keyword_lookup.zig` 表项 **87** 枚 − **7** 枚外族词（`go`/`get`/`set`/`lock`/`with`/`from`/`struct` 在 PHP **不是**关键字 ⇒ 改走「过度识别」反例组，见 §3.4.2）− **1** 枚 `yield`（超出 AOT 范围，宪法 §七-1 生成器）= **79 形**（`k_` 72 + 魔术常量 `m_` 7）。

**测法**：一形一模板、**两个只差拼写的臂** —— `ctrl` 臂用表内拼写（关键字为全小写、魔术常量为大写）⇒ 应即 PHP 语义基线；`probe` 臂用 Title 拼写 ⇒ 任何跨臂差异**不可**归因于模板。每形独立文件、独立编译、类名/函数名逐形专属。

**注册读数（两轮修门后的全量跑，`ELAPSED=595s` = 6.0 s/形，共 100 形 = 79 主群 + 21 反例组，每形两次 AOT 编译 ⇒ `arms=200`）**：
`C010H_DONE shapes=79 arms=200 face=59 noface=15 confounded=5 bad_probe=0 ctrl_compile_fail=1 probe_compile_fail=25 probe_timeout=0 inverse_shapes=21 inverse_face=15 inverse_noface=6 inverse_confounded=0 repo_build_residue=0 SMOKE_ONLY=0`
（主群计数 `face/noface/confounded/ctrl_compile_fail/probe_compile_fail` 与首跑、第一轮修门跑之间**逐字节不变**；两版首跑读数**禁止引用**，见 §3.4.4-1 与 §7-11。）

#### 3.4.1 主群 79 形类分布

| 类 | 计数 | 构成 | 判读 |
|---|---|---|---|
| **FACE**（探针臂可运行但与 PHP 不等值） | **34** | `k_` 28 + `m_` 6 | 混合大小写拼写在运行期改变行为 |
| **FACE_PROBE_COMPILE_FAIL**（探针臂 AOT 无产物） | **25** | 全 `k_` | 严格文法位 ⇒ 直接**编译失败**（§3.1 C 类的穷举面） |
| **NOFACE**（探针臂与 PHP 逐字节等值） | **15** | 全 `k_` | **成因已由 §3.5 判别 = 14/15 属文法位过度宽容**，非「已支持大小写」 |
| **CONFOUNDED_CTRL_DIFF** | 4 | `k_and`、`k_goto`、`k_iterable`、`m_namespace` | **ctrl 臂自身**就与 PHP 不等值 ⇒ 与大小写无关的独立缺陷（见 §3.4.3） |
| **CONFOUNDED_CTRL_COMPILE_FAIL** | 1 | `k_var` | 同上：小写 `var $p` 声明在 AOT **编译失败** |

⇒ **R-2 的真实验收面 = 59 形**（34 FACE + 25 探针编译失败），其中 **2 形为文本噪声红**（见 §3.4.4）⇒ **语义红面 57 形**。覆盖面由侧门 E 的 19 形扩至 **79 形**、红面由 E 的 **11 枚**（8 DIFF + 3 编译失败）扩至 **59 枚**，并新增覆盖 E 未测的 `elseif`/`switch`/`case`/`default`/`try`/`catch`/`throw`/`use`/`extends`/`implements`/`interface`/`trait`/`enum`/`match`/`fn`/`readonly`/`abstract`/`clone`/`instanceof`/`include`/`require`/`and`/`or`/`xor`/`goto`/`var`/`iterable`/`callable`/`mixed`/`object`/`never`/`void`/`final`/`const`/`namespace`/`global`/`do`/`while`/`for`/`foreach`/`endwhile`/`endfor`/`endforeach`/`endif`/`endswitch` 等族。

**FACE 的语义结局四分（对注册 TSV 的探针臂 AOT 侧逐行归一实测，脚本 `c010h_face_split_tmp.awk`）**

| 结局 | 计数 | 形 | 与 §3.1 的对应 |
|---|---|---|---|
| **FATAL**（rc≠0 或致命/错误消息） | **13** | `k_if` `k_list` `k_self` `k_class` `k_while` `k_catch` `k_unset` `k_array` `k_elseif` `k_parent` `k_declare` `k_callable` + `k_static` | B 类（当函数调用）/ 声明注册表落空（类未注册）；`k_static` 的 AOT 侧消息为 `ERROR: Property KwhSt1.n not found`（**非** `Fatal error:` 前缀 ⇒ 本门另一张消息形态）。其成因**推断**为「`Static` 修饰头被跳过 ⇒ 属性未登记为静态」，与 §3.5 的 `n_public`/`n_private` 同支，**未经发射侧取证** ⇒ 禁止在 R-2 评审中当证据引用 |
| **SILENT_EMPTY**（剥掉警告后 AOT 无任何输出） | **12** | `k_echo` `k_case` `k_print` `k_throw` `k_return` `k_default` `k_include` `k_require` `k_include_once` `k_require_once` + `m_method` `m_function` | **A 类零指令**在穷举面上的规模：10 枚语句/结构关键字 + 2 枚魔术常量（`return __Method__;` 返回**空串** ⇒ 整个文件零输出） |
| **WRONG_VALUE**（无错误消息、值不同） | **7** | `k_true` `k_break` `k_continue` `m_dir` `m_file` `m_line` `m_class` | 最危险：`k_break` PHP `b` vs AOT `bbbbb`（`break` 被忽略 ⇒ 跑满 5 轮）、`k_continue` PHP `4` vs AOT `6` ⇒ **控制流语义被改写且 rc=0**；四枚魔术常量为 `strlen(...)>0 ? "ok" : "x"` 形态 ⇒ AOT 一律落 **false 支**打 `x`（坍成的裸名是空串/0） |
| **仅警告噪声**（剥离 `Warning:` 行后与 PHP 逐字节等值） | **2** | `k_null` `k_false` | **文本噪声红，非语义红** ⇒ 见 §3.4.4 的口径局限 |

**25 枚探针编译失败名单**（AOT 在 Title 拼写下不产出二进制；这些文法位**没有**「裸标识符」容忍支）：
`fn` `as` `or` `new` `for` `use` `try` `xor` `enum` `trait` `clone` `match` `switch` `extends` `foreach` `abstract` `function` `readonly` `interface` `protected` `implements` `instanceof` `endwhile` `endfor` `endforeach`
⇒ 与 §3.5 的 NOFACE 名单对照可得**文法位三分**：严格位（编译失败）／宽容位（NOFACE，靠 `eatKeywordAsIdentifier` 才绿）／坍成表达式位（FACE，运行期显形）。注意 `protected` 属严格位而 `public`/`private` 属宽容位 ⇒ **同一语义族的三个修饰词落在三类不同结局**，禁止按「可见性修饰」整族外推。

#### 3.4.2 反例组（过度识别面孔）：**7 词 × 3 名位 = 21 形实测**

**测法（与主群同双臂法）**：`alias` 臂用瞎词 `zzkwh*`（证明模板本身合法 PHP、且 AOT 在该名位接受任意标识符）⇒ 该臂必须与 PHP 等值，否则整形归 `CONFOUNDED_*`；`collide` 臂把同一位置换成表内真实词（`go`/`get`/`set`/`lock`/`with`/`from`/`struct`）⇒ **PHP 8.5.8 视其为普通标识符**，故 `collide` 臂一旦红即证明 AOT **把非保留词抢注成了关键字 token**（= 表内条目的直接后果，与大小写无关）。

| 名位（模板） | 实测 | 逐词读数 | 判读 |
|---|---|---|---|
| **顶层函数名**（`invf_*`：`function @ID@(): int { return 10N; } echo @ID@();`） | **7/7 红** | 七枚全为 `collide(COMPILE_FAIL:<值>\|<none>)` | AOT 在顶层函数名位**直接拒绝**这七个非 PHP 关键字 ⇒ 合法 PHP 脚本无法编译 |
| **类名**（`invd_*`：`class @ID@ {} echo (new @ID@() instanceof @ID@) ? 20N : …;`） | **7/7 红** | 七枚全为 `collide(COMPILE_FAIL:<值>\|<none>)` | 同上，类名位亦为硬名位 |
| **方法名**（`invm_*`：`class KwhI<N> { public function @ID@(): int { return 30N; } } echo (new KwhI<N>())->@ID@();`） | **6 绿 / 1 红** | `go/get/set/lock/with/from` = `collide(RUN:30N\|30N)` NOFACE；**`invm_struct` = `COMPILE_FAIL`** | 方法名位**有**关键字容忍支 ⇒ 六词可用；`struct` 例外 ⇒ 机制见下 |

⇒ 组内总计 **`inverse_face=15 inverse_noface=6 inverse_confounded=0`**（`bad_probe=0` ⇒ 21 形双臂均经 `php -l` 预检通过，无坏探针）。

**机制到行（只读实文核对，非推断）**：
- 顶层函数名 `parser.zig:1405 const name_tok = try self.eat(.t_string);`（紧随 `:1406` 的原文切片 intern）；类/容器名 `:1319-1321` = `if (self.syntax_mode == .go and curr == .t_go_identifier) eat(.t_go_identifier) else try self.eat(.t_string)` ⇒ **PHP 模式恒落硬 `.t_string` 分支**（`t_go_identifier` 支只在 Go 模式启用），紧随 `:1322` 的原文切片 intern。两处均**无** `eatKeywordAsIdentifier` 兜底支 ⇒ 一旦 lexer 把 `go` 查表成 `.k_go`，这两处即 `Parse error: unexpected token "go", expecting identifier` ⇒ 解释 `invf_*`/`invd_*` 的 14 枚红。
- 成员名 `:762`（`parseClassMemberWithModifiers`）/`:946`（`parseClassMember`）为三段式 `t_go_identifier → t_string → eatKeywordAsIdentifier() → 兜底 eat(.t_string)` ⇒ 走 `:3843 eatKeywordAsIdentifier` → `:3761 isKeywordIdentifierTag`。
- **实测更正（本节的第二项事实）**：`isKeywordIdentifierTag`（`:3761`–`:3840`）实际列出 **74** 枚 `.k_*` tag，**不是**本单 §4 旧措辞所称的「全部 87 枚」。表内有、容忍清单**无**的 **6** 枚 = `.k_endfor` `.k_endforeach` `.k_endif` `.k_endswitch` `.k_endwhile` `.k_struct` ⇒ **`invm_struct` 唯一红形即由 `.k_struct` 被排除这一枚直接解释**（其余五枚 `end*` 在本组无对应词，但其名位结局必然同形）。

**三枚补充探针（逐形单文件实测，均为「今日为绿」的形态事实）**
| 探针 | PHP | AOT | 结论 |
|---|---|---|---|
| `function Get(): int { return 1; } echo Get();` | `1` | `1` rc=0 | 混合大小写**外族词**函数名今日**能编译**（因 `Get` 查表落空 ⇒ 坍成 `t_string` ⇒ 过硬名位） |
| `$o = new stdClass(); $o->go = 1; echo $o->go;` | `1` | `1` rc=0 | 属性读写位对 `.k_go` 宽容（`:2465/:2524/:2563` 名位调用） |
| `struct` 当方法名（= `invm_struct` 同模板重跑 3 次） | `307` | **COMPILE_FAIL**（`Parse error: unexpected token "struct", expecting identifier`）×3 | **确定性**复现，非门抖动 ⇒ 与 §3.4.4 曾疑的「不可复现」无关（该疑点系误读首轮输出，已作废） |

**⇒ 对 R-2 的落地约束（本节最重要的一条预测）**：上面第一枚补充探针给出的是**今日绿、修后可能红**的形 —— R-2 把查表改成忽略大小写之后，`Get`/`With`/`Set` 一类**混合大小写外族词**将首次命中 `.k_get`/`.k_with`/`.k_set` ⇒ 顶层函数名（`:1405`）与类名（`:1321`）两处硬 `eat(.t_string)` **原本靠查表落空而侥幸通过**的脚本会**新增编译失败面**（今日实测该面为 0 红 ⇒ R-2 之后不为 0 即为回归）。⇒ **R-2 若只改 lexer 查表，必须同时在这两处名位补 `eatKeywordAsIdentifier` 兜底**（并在 `:1406`/`:1322` 继续 intern **原文切片**，先例即同函数 `:3857` 的 `self.lexer.buffer[name_tok.loc.start..name_tok.loc.end]`），否则「消 59 枚红面」会以「新增外族词名位红面」为代价 ⇒ 该面以 §3.4.2 本 21 形矩阵 + 上述 `function Get()` 探针为**守卫臂**（判据 5 的量化形态，见 §3.4.5-4）。

#### 3.4.3 五枚与大小写无关的默认档独立缺陷（CONFOUNDED 组，实测到行）

| 形 | ctrl 臂（表内拼写 ⇒ **探针内无大小写面孔**） | PHP 8.5.8 | AOT | 结论 |
|---|---|---|---|---|
| `k_and` | `$r = (1 < 2) and (3 < 2); echo $r ? "y" : "n";` | `y` | `n` rc=0 | **小写 `and` 在括号操作数组内求值错**（静默，无任何消息）⇒ 与大小写无关，须另归因；注意 `k_or`/`k_xor` 的 ctrl 臂**均绿**（其红面只在 Title 拼写）⇒ 本枚是该族唯一「表内拼写即红」的形 |
| `k_var` | `class KwhV1 { var $p = 3; } echo (new KwhV1())->p;` | `3` | **编译失败** | AOT **不支持** PHP 的 `var` 属性声明形式；反直觉处 = 大写 `Var` 与瞎词 `Zkwhq` 反而**能编译**（走 §3.5 的宽容支）⇒ 支持面缺失被宽容支掩盖 |
| `k_goto` | `$i = 0; KWH_LBL1: $i++; if ($i < 2) { goto KWH_LBL1; } echo $i;` | `2` | **空输出** | 小写 `goto` 形使 AOT **整个尾部消失**（连 `echo $i` 都没打）⇒ 标签/跳转面缺失，同属 §3.1 A 类零指令形态但与拼写无关 |
| `k_iterable` | `function kwh_it1(iterable $a)` 传数组 | `2` | `Fatal … must be of type iterable, array given` | **`iterable` 类型位拒绝数组**（PHP 语义应接受 Traversable\|array）⇒ 独立类型面缺陷；消息内参数名渲染为 `$$a`（双 `$`）为第二处消息形态问题（`k_callable` 探针消息同样出现 `$$f`） |
| `m_namespace` | `namespace KwhNsM1; echo strlen(__NAMESPACE__)` | `7` | `0` | **`__NAMESPACE__` 在命名空间声明后取到空串** ⇒ 独立缺陷（且该形 Title 臂还叠了 lexer 面孔，故两臂同红） |

⇒ **宪法 §五 的处理**：这五枚**不属**本单的 lexer 根，R-2 落地**不会**消掉它们；本单只登记，是否立单待老铁裁决（见 §7-12）。

#### 3.4.4 口径局限与两处门侧固化坑（**先修门、后引用**）

1. **坏探针（本门首跑的实际错误）**：`k_callable` 模板把闭包写成 `fn(): int { return 15; }`（Go 风格），**PHP 8.5.8 自己就报** `Parse error: unexpected token "{"` ⇒ 双臂同败、该形被误分类为 `CONFOUNDED_CTRL_COMPILE_FAIL`，并使 §3.4.3 的独立缺陷名单一度含 `callable`。⇒ 修正 = 改用 PHP 闭包语法 + **在每臂执行前加 `php -l` 预检**并新增 `BAD_PROBE_*` 两类。修门前后：`face 58→59`、`confounded 6→5`、`bad_probe=0`。⇒ **规则**：红面归因前必须先证明探针自身是合法 PHP，否则「AOT 也报错」可能正是 AOT 的**正确**行为。首跑读数**禁止引用**。
2. **`norm()` 口径窄于侧门 G**：门 H 的归一只剥离**行首** `PHP ` 前缀、不折叠双空格 ⇒ 上表「仅警告噪声」两形（`k_null`/`k_false`）的红是**文本**差异。已按「剥离 `Warning:` 行后逐字节比对」复算分离语义红面（57）。**不回改门 H 的 `norm()`**（其总数已登记），但引用 FACE 计数时**必须同时给出 34（含噪声）/ 32（语义）两个数**。
3. **顺带观察（未归因、未立单）**：AOT 对同一未定义变量**连打两行**警告 —— `Warning:  Undefined variable True` 与 `Warning: Undefined variable True`（差一个双空格），而 PHP 只打一行 `PHP Warning: …`。出现在全部含 `Undefined variable` 的 FACE 行 ⇒ 属警告发射点重复，与本单的 lexer 根**无关**（小写臂不出现）。登记 §7-13。

#### 3.4.5 对 R-2 评审可直接使用的验收判据（实测给出）

1. **`face → 0` 且 `probe_compile_fail → 0`**（59 形全数收敛）；
2. **`noface=15` 必须仍绿，但须比对生成码**：其绿当前来自宽容支（§3.5 结论 1），若 R-2 后仍逐字节等值却走的是关键字支 ⇒ 才算收口（教训同 §3.1 D 类：**计数差对落点缺陷零分辨力**）；
3. **`confounded=5` 应收敛为臂间一致而非转绿**：这五枚与拼写无关 ⇒ 若修复后 ctrl/probe 两臂输出相同即达标，**不要求**与 PHP 等值（等值需另立单修）；
4. **反例组（21 形）双向守卫**：
   - **不得变大**：当前注册读数 `inverse_face=15 inverse_noface=6 inverse_confounded=0` ⇒ R-2 若把「忽略大小写查表」实现成「词表即保留字表」，`invm_*` 的 6 枚绿会转红（`inverse_face → 21`）即越界；
   - **也不得原样保留**：这 15 枚红的根是**表内含外族词**（`go/get/set/lock/with/from/struct`），与大小写无关 ⇒ R-2 **不应**消掉它们（消掉即说明改的是保留词集合而非大小写敏感，属越界）；
   - **新增红面反查（本判据的实测出处 = §3.4.2 补充探针 1）**：`function Get()` / `class With()` 一类混合大小写外族词名位**今日为绿**（查表落空）⇒ R-2 落地后若这类形改走 `.k_get`/`.k_with` 而在 `:1405`/`:1321` 硬名位编译失败，即为**修复新增的回归**，必须与名位容忍支补洞同批落地。
5. **魔术常量组（`m_*` 6 形红）是 R-2 的实现陷阱判据**：表内键为大写拼写，若归一化方向取反（把原文折成小写再查表）⇒ 这 6 形将由红转**更红**（丢命中）。

### 3.4.6 R-2 批落地实测（2026-10-07，D-1 甲 + D-2 分叉；验收 = 本节读数，非估算）

**落地形态**：旗标门控分叉 —— `Lexer.case_insensitive_keywords` 仅由 AOT 编译入口（`main.zig` 单文件 + `multi_file_compiler.zig`）经 `Parser.initWithModeInsensitive` 置 true；解释器/字节码构造点缺省 false ⇒ 两模式 token 流逐字节不变。查表归一方向 = **原文折小写查 80 枚 k_ 键 + 原文折大写查 7 枚 m_ 键**（两族键字母大小写互斥 ⇒ 无交叉误命中），token 文本仍交原始切片。

**首轮落地被门 H 实测打回的证据（名位长尾）**：首批只补工单编目的 `:1405`/`:1319-1321` 两处 ⇒ 门 H `inverse_face 15→14`（仅 `invm_struct` 经扩展 tag 转绿）且守卫探针 `function Get()…echo Get();` / `class With…new With() instanceof With` 由今日绿转 **COMPILE_FAIL**（失败点后移到调用位/`new` 位/`instanceof` 位，工单原编目未覆盖）⇒ 第二批补 13 处名位（调用位=parsePrimary else 臂、new 位经 parsePrimary 自动、instanceof 位、类型位=parsePrimaryType 旗标 catch-all + **内置类型名规范小写 intern**（修 `Callable` TypeError 残面）、namespace/use/别名/分组 use/属性/enum case/const/goto 标签/catch 类型/`${name}`）+ 第四面孔（`main.zig` 多文件检测与 `dependency_resolver.matchKeyword` 折形 —— `Include "x";` 漏检 ⇒ 误走单文件 ⇒ include_stmt 在单文件 IR 层无人消费而整句静默）。复跑门 H ⇒ `inverse_face=1`、`face=1`。

**验收读数（链 II，六门 + 影子 + 主回归全绿）**：

| 门 | 修复前（冻结代次） | 落地后（本代次） | 判读 |
|---|---|---|---|
| E | same=8 diff=8 silent_empty=3 aot_fatal=3 compile_fail=3 | **same=19 diff=0 silent_empty=0 aot_fatal=0 compile_fail=0** | §6 预期全中 |
| F | same=4 diff=4 zero_instr=1 | **same=8 diff=0 zero_instr=0** | A 类零指令消灭 |
| G | same=4 diff=3 | **same=7 diff=0 red_confirmed=0 guard_same=4 guard_red=0** | R-2b 收口且守卫臂未越界 |
| H 主群 | face=34 probe_compile_fail=25 noface=15 confounded=5 | **face=1 probe_compile_fail=0 noface=73 confounded=5** | 残面 = `k_unset`（`Unset($a[0])` 调用名解析精确匹配漏大写 ⇒ **函数名大小写不敏感解析**独立缺陷，修复前同面同 Fatal，非回归；§8 并入） |
| H 反例组 | inverse_face=15 inverse_noface=6 | **inverse_face=1 inverse_noface=20** | 残红 = `invf_go`（`function go()` 已能编译，运行期输出空 ⇒ 外族词 `go` 与运行期 `go` 构造碰撞，属「表内含外族词」家族，判据 4 明言 R-2 不消；§8 并入）；`invf/invd` 其余 14 枚经名位容忍支转绿 |
| H2 | over_accept=14 strict_same=1 | **over_accept=14 strict_same=1** | 瞎词臂不受影响（成因面不变） |
| I | aot_same=8 aot_diff=8 compile_fail=3 both_red=11 vm_only_red=1 | **aot_same=19 aot_diff=0 compile_fail=0 both_red=0 vm_only_red=12**；**tree/bc 四项读数逐项不变** | D-2 分叉达成：VM 侧 12 枚红面按裁决保留现状 |
| 影子 | — | **68/68 形 `main.zig` md5 逐字节一致** | 冻结基线零漂移（发射中性实测成立） |
| 主回归 | Pass 67 / Skip 1 | **Pass 67 / Skip 1**（2026-10-07 17:24:11 报表） | 基线保持 |

**落地后已知边界（登记，未修）**：① 标签**定义**位 `Get:` 语句路由走 `.t_string` 专用臂 ⇒ 关键字名标签定义会解析失败（预路由需枚举 80 枚 tag、误劫持语句臂风险大，未做）；② `parseCallArg` 命名参数名位仍用基础 74 枚清单（未并入扩展 6 枚）；③ 表达式位 `echo Include "f";` 经容忍臂坍成变量（无效形态的过度接受，与代码库既有容忍风格一致）；④ `Unset()/Get()` 类**函数名大小写不敏感解析**缺失（PHP 函数名本不区分大小写）⇒ 残面 k_unset 所在，需动运行期函数注册表查名，另批。

### 3.5 十五枚 NOFACE 的成因判别（**永久侧门 H2 = 同位换瞎词门**，任务 #120 新立，实测 `C010H2_DONE shapes=15 over_accept=14 strict_same=1 aot_compile_fail=0 php_ok_aot_diff=0 repo_build_residue=0`，`ELAPSED=54s` = 3.6 s/形）

**问题**：侧门 H 有 15 形的混合大小写臂与 PHP **逐字节等值**（NOFACE）。但全树**不存在任何大小写折叠通道**（实测 `grep -n 'eqlIgnoreCase|ascii.lower|toLower|equalsIgnoreCase'` 于 `src/compiler` ⇒ **0 命中**；`std.ascii.*` 仅 `isAlphabetic/isAlphanumeric/isDigit/isHex` 等字符类判断）⇒ 这 15 形**不可能**经关键字查表命中 ⇒ 绿必来自「坍成 `t_string` 之后被文法位接受」。

**判别法**（不比谁对，只比「**AOT 是否接受 PHP 不接受的东西**」）：把同一模板的关键字位替换成语法上不存在的标识符 `Zkwhq` ⇒
`over_accept` = PHP 报错而 AOT 正常输出 ⇒ 该文法位对**任意标识符 token** 宽容 ⇒ 侧门 H 的绿是「宽容得绿」，**不是**「已正确支持大小写」。

| 形（=侧门 H 的 NOFACE 形） | 关键字位 | PHP 8.5.8 瞎词臂 | AOT 瞎词臂 | 判读 |
|---|---|---|---|---|
| `n_else` | `else` 中段 | `Parse error: unexpected token "{"` | `else_ok`（**块照执行**） | over_accept ⇒ **与 §3.1 D 类同机制** ⇒ `k_else` 的 SAME 属偶然等值 |
| `n_finally` | `finally` 中段 | `Parse error: unexpected token "{"` | `xfinally_ok`（catch 跳过 + 块无条件执行） | over_accept ⇒ 同上 |
| `n_do` | `do` 头 | `Parse error: unexpected token "{"` | `do_ok` | over_accept |
| `n_endif` | `endif`（替代语法终止位） | `Parse error: … expecting "elseif" or "else" or "endif"` | `endif_ok` | over_accept ⇒ **替代语法（`if:`…`endif;`）的终止位不校验** |
| `n_endswitch` | `endswitch` | `Parse error: … expecting "endswitch" or "case" or "default"` | `s` | over_accept ⇒ 同上 |
| `n_const` | `const` 声明头 | `Parse error: unexpected identifier "KWH_C1"` | `5`（常量竟已定义） | over_accept ⇒ 声明头被丢弃后其余部分仍成立 |
| `n_namespace` | `namespace` 头 | `Parse error: unexpected identifier "KwhNs1"` | `20` | over_accept |
| `n_global` | `global` 语句 | `Parse error: unexpected variable "$G"` | `10` | over_accept |
| `n_final` | `final class` | `Parse error: unexpected token "class"` | `final_ok` | over_accept |
| `n_public` | `public $x` | `Parse error: … expecting "function"` | `4` | over_accept ⇒ 可见性修饰位被容忍 |
| `n_private` | `private $v` | `Parse error: … expecting "function"` | `11` | over_accept ⇒ 同上 |
| `n_void` | 返回类型 `: void` | `Fatal: Return value must be of type Zkwhq, none returned` | `void_ok` | over_accept ⇒ **未知返回类型名不参与校验** |
| `n_mixed` | 返回类型 `: mixed` | `Fatal: … must be of type Zkwhq, int returned` | `7` | over_accept ⇒ 同上 |
| `n_object` | 返回类型 `: object` | `Fatal: … must be of type Zkwhq, stdClass returned` | `object_ok` | over_accept ⇒ 同上 |
| `n_never` | 返回类型 `: never` | `never_ok`（**PHP 也 rc=0**） | `never_ok` | **零判别力** ⇒ 返回类型仅在真正返回时解析，`throw` 形从不触发校验 ⇒ 该形成因未定，登记 §7 |

⇒ **三条可直接用于评审 R-2 的机制结论**：
1. **15 枚绿面中至少 14 枚不是「已支持」**：块位（`else`/`finally`/`do`/`endif`/`endswitch`）绿在「裸名被跳过后 `{…}` 仍作独立块无条件执行」，声明位（`const`/`namespace`/`global`/`final`/`public`/`private`）绿在「整条修饰语句被静默丢弃后剩余语义恰好成立」⇒ **R-2 落地后这 15 形仍应 SAME，但语义路径必须改变** ⇒ 复测**禁止只看 SAME 计数**，须比对生成码（教训同 §3.1 D 类：`instr` 计数对落点缺陷**零分辨力**）。
2. **类型位是另一张独立面孔**：三枚返回类型形证明 AOT 对**未知/非规范拼写的返回类型名不做校验**（PHP 侧 Fatal）。⇒ 本门**未测**「AOT 对已知返回类型（`: int` 等）是否校验」；已核对 `AOT-TYPE-001` 单为 **PHI 节点类型混接**（状态 CLOSED），**不覆盖**返回类型声明校验面 ⇒ 该问题当前**无工单归属**，若要定面须另立门/另立单（近邻仅 AOT-RUNTIME-002 G4 的 typed 槽六面），禁止由本表外推。
3. **`k_var` 与本门呈镜像**：侧门 H 里小写 `var $p` 声明**编译失败**，而瞎词 `Zkwhq $p` 与大写 `Var $p` **都能产出预期值** ⇒ 名位/修饰位的容忍支是当前「绿」的实际来源，`var` 的支持反而缺失（登记为 §3.4 的 CONFOUNDED 独立缺陷之一）。

**固化坑（跑前静态核对抓到，未产生坏读数）**：门 H2 首版循环变量为 `sid`，四处文件路径却写 `$s` ⇒ `set -u` 下会**整门静默中止**；已改 `$sid`，并补 `ONLY=` 循环级过滤（同门 I 的坑，见 §6）。

#### 3.5.1 任务 #125 修门：H2 补 `BOTH_REJECT` / `AOT_ONLY_RED` 分桶（**纯门改动，零 `src/` 改动**，2026-10-09）

**缺陷（R-3 落地轮踩到，见 §3.6「R-3 批落地实测」）**：本门首版只有四桶（`OVER_ACCEPT` / `SAME_BOTH_ERROR_LIKE` / `DIFF_PHP_OK_AOT_DIFF` / `AOT_COMPILE_FAIL`），而 **`AOT_COMPILE_FAIL` 把「PHP 也拒（收敛）」与「PHP 通过而 AOT 拒（真回归）」压成同一枚计数** ⇒ R-3 后 `aot_compile_fail` 从 0 跳到 2 时，只能靠**人工逐形回读 `php_rc`** 才能判明那是收敛。本门作为长期守卫门，方向判别必须制度化。

**口径（已固化进门尾注释）**：**AOT 拒 ≠ 红。PHP 同拒 ⇒ 收敛（`BOTH_REJECT`）；PHP 通过而 AOT 拒 ⇒ 真回归（硬守卫列 `aot_only_red`，必须恒 0）**。

| 改动 | 内容 |
|---|---|
| 判向前置 | 新增 `php_err` 计算并**上移**到编译失败分支之前（旧版该分支**完全不判向**，见下方 git 取证） |
| 拒绝支拆分 | 产物不可执行时（规则 21：`--compile` 解析失败仍 `rc=0`，只能以**产物存在性**判）⇒ `php_err=1` 记 **`BOTH_REJECT`**、`php_err=0` 记 **`AOT_ONLY_RED_COMPILE`**；两支均把编译日志经归一后写入 `aot_log=` 列（旧版拒绝行不记录 AOT 侧文本，无法复算报错位置） |
| 运行侧补守卫 | `php_rc=0` 而 AOT `arc!=0` 或输出含 `Fatal/Parse error` ⇒ 记 **`AOT_ONLY_RED_RUN`**（旧版落入 `DIFF_PHP_OK_AOT_DIFF`，与「输出不同」混计） |
| 归一口径对齐 | 新增 `normlog()`：剥行首 `Error: `、行号归 `LINE`、`/tmp/…` 归 `TMPDIR` ⇒ 与门 J `:54` **逐字同口径**（新登记的 `aot_log=` 列必须走它，否则原始日志含随机临时目录 `/tmp/c010h2.XXXXXX`，跨 run 不可比） |
| 代次锚点 | 表头补 `# parser_md5=`（原仅 `compiler/lexer/keyword_lookup` 三枚；本门判据落在 parser 文法位，缺该锚点无法自证代次） |
| 总数行 | 新增 `both_reject` / `aot_only_red` 两列；**`aot_compile_fail` 语义更正为「拒绝总数」= `both_reject + aot_only_red`**（保持历史列不删、口径变更须读分列） |

**旧版门实文取证（不靠记忆，取已入库 blob `73f4d6b:fuzzy_scripts_720/tmp/c010_noface_tolerance_gate_tmp.sh`）**：`:76-80` 的拒绝支为

```bash
if [ ! -x "$T/aot_compile_c010h2_${sid}_tmp" ]; then
  echo "$sid|php_rc=$prc|aot_rc=NA|AOT_COMPILE_FAIL|$php_n||<none>" >> "$OUT"
  CF=$((CF + 1))
  continue
fi
```

⇒ 拒绝支**只写 `php_rc=` 数字、不做任何判向**（`php_err` 仅在 `:84` 的运行路径分类里出现），AOT 侧文本固定写 `<none>`，表头也无 `parser_md5` ⇒ 「收敛 vs 真回归」在旧表结构上不可判，必须靠人工回读 `php_rc`。

**修门证明（先修门、后引用）**：与 R-3 代次快照 `c010_r3_presnap/c010_noface_tolerance_r3gen_tmp.tsv`（md5 `7577d51ce6181a84102f5d35d49459ae`）逐字节 `diff` ⇒ 差异行 **12** 枚，分解为「表头 4（`parser_md5`/`columns`/`verdicts` 新增与改写）+ 数据 2 形改写（`n_endif`/`n_endswitch`：`AOT_COMPILE_FAIL` → `BOTH_REJECT`，旧 2 + 新 2 = 4 行）+ `ELAPSED` + 总数行」；**判据数据行 13/15 逐字节全等**（`comm -12` 实测）⇒ 修门只动分类与日志列，未扰动任何一形的 PHP/AOT 结局。

**新代次注册读数（全量，`SMOKE_ONLY=0`，先 `ONLY=n_endif,n_endswitch` 冒烟）**：

```
C010H2_DONE shapes=15 over_accept=12 strict_same=1 aot_compile_fail=2 both_reject=2 aot_only_red=0 php_ok_aot_diff=0 repo_build_residue=0
ELAPSED=44s
```

⇒ 判定列与 R-3 代次**逐项等值**（`over_accept=12` / `strict_same=1`），首次把「2 枚拒绝」显式记为**收敛**并给出 AOT 侧报错原文（`Parse error: syntax error, unexpected end of file, expecting "endif"` / `expecting "endswitch", "case" or "default"`），硬守卫列 `aot_only_red=0` 转正即真回归。

**注册锚点（脚本定稿后同命令取四枚，防 §3.6 的「md5 早于定稿」坑）**：脚本 `fuzzy_scripts_720/tmp/c010_noface_tolerance_gate_tmp.sh` md5 `582ca74d50ff85567ac933b0f85dc7b3` / 116 行（mtime 11:09:11）→ 表 `c010_noface_tolerance_tmp.tsv` md5 `0663be8da1ef8f17449d5409937b6f87`（mtime 11:10:05，**晚于脚本** ⇒ 该 md5 即本读数生成版）；二进制 `81f8a55a989f9a793fec2f75c32fd37d`、`parser.zig` `5ad452fe4bc250b4732cbb3a2827b28a`（与 R-3 代次全等 ⇒ 零 `src/` 改动自证）。

### 3.6 替代语法（`endif;` / `endswitch;` 族）真实支持性取证（**永久侧门 J = §7-15 的收口门**，2026-10-08 实测，`ELAPSED=77s` / 23 形 = **3.3 s/形**）

**为什么必须另建一张门**：侧门 H2 只做「关键字位换瞎词 `Zkwhq`」，其 `n_endif`/`n_endswitch` 两形证明的是**该文法位对任意标识符宽容**，**推不出**替代语法已实现 ⇒ §7-15 只能登记为「不可判」。本门直接写替代语法的正/负例，与拼写无关，是独立面孔。

**读码前提（实文核对，全部锚点在本代次 `parser.zig` md5 `e3987a36…` / 4230 行上逐条 `awk` 复验）**：五支路齐备且产出**标准 AST 节点** ⇒ **发射侧语法无关**（这是「正例全绿」的结构性原因，非侥幸）。

| 支路 | 锚点 | 关闭标记消耗形态 |
|---|---|---|
| `if` | `:1495` 判 `.colon`、`:1500` `parseAlternativeBody(.k_endif)`、`:1503-1514` elseif/else 链、`:1515-1517` | **软**：`if (self.curr.tag == .k_endif) { nextToken(); eat(.semicolon); }` ⇒ 缺 `endif` **不报错** |
| `while` | `:1577-1580`、`:1581` | **硬**：`_ = try self.eat(.k_endwhile)` |
| `foreach` | `:1671`、`:1672` | **硬**：`eat(.k_endforeach)` |
| `for` | `:1832`、`:1833` | **硬**：`eat(.k_endfor)` |
| `switch` | `:3520` 判 colon、`:3531` `end_token=.k_endswitch`、`:3556-3558` `self.nextToken(); // Skip unexpected tokens`、`:3563-3565` | **软** + 意外 token **整枚跳过** |
| 体扫描 | `parseAlternativeBody:1592-1604`，循环条件 `:1594` = `curr != end_tag and curr != .eof` | **EOF 静默收尾**；`:1596` 仅在 `end_tag==.k_endif` 时另停 `elseif`/`else` ⇒ **异种 end 标记不停** |
| 语句层兜底 | `:482` `else => self.parseExpressionStatement()` → `:2426-2430`（`:2428` 软分号）→ `parsePrimary` 兜底 `:3295-3309` | R-2 甲批新增的 `:3299-3305` 在旗标开启时把**容忍清单内关键字 tag**（含 `isAotExtendedKeywordIdentifierTag:3916-3927` 的 5 枚 `end*`）当标识符接成 `.variable` ⇒ **裸 `endif;` 在语句位被静默吃成一条变量表达式** |

**门资产与三轮读数（先修门、后引用）**
- **v3**（R-3 落地轮，2026-10-09）：脚本 `fuzzy_scripts_720/tmp/c010_alt_syntax_gate_tmp.sh` md5 `592ef97458d6ae7e044e97ad6289fd69`，头行 `# gate_rev=v3`、`# positive_shapes=19 negative_shapes=10`，29 形（正例 16+3、负例 7+3）→ 表 md5 `2a25520cf7e4e78362a6be601e7cc5f6`（含 `ELAPSED=70s` 行；跨 run 复证时按 v2 口径先把耗时行归一）。
  - **★ md5 更正（2026-10-09 复测）**：本行曾登记 `1ff97d51a8be8bbddc8642f638a05b8e`，该值是「加完 6 形、尚未改头行 `gate_rev`／`positive_shapes` 两行」时的中途读数 ⇒ 不是产出注册读数的高亮版。判定依据为实测时序：脚本 mtime `09:46:35` **早于** 表 mtime `09:47:54`，且此后脚本未再被编辑 ⇒ 09:47:54 那轮跑的就是 `592ef974…`。教训：**脚本改完（含头行的自证戳）再取 md5，并在同一条命令里同时抓脚本与表的 md5**，否则登记的正是"上一版脚本"。
  - v2→v3 只加形不改判据：正例补 `p_if_elseif_multi` / `p_if_else_multi` / `p_if_elseif_chain_multi`（**elseif/else 臂多语句**——若不补这三枚，硬 `eat` 落地会把 PHP 合法写法误拒，而旧 16 形全是单语句臂、抓不到该误拒）；负例补 `n_switch_stmt_before_case_alt`（替代语法 `case` 前裸语句）/ `n_else_no_endif` / `n_elseif_no_endif`（缺闭合的两个臂形态）。
- **v2**：脚本 md5 `69806529f6bdf8feb2919dcac182db07` → 表 md5 `8b208dd0b9123c5f6bc8ee306cda5360`（首轮）／`6d4dc390aef69c916ed1fa171b5f8aaa`（第二轮，仅 `ELAPSED` 行不同）；头行四枚代次戳 `compiler_md5=5beb1591… / lexer e3dd4191… / keyword_lookup ef70993a… / parser e3987a36…`，并带 `# gate_rev=v2`。
  - **★ 入库更正（2026-10-09 实测）**：v2 的门脚本与第二轮 TSV **已随 commit `73f4d6b` 入库**（上一版此处写的「均未入库、`git show 0652130:` 取不到」已失效）⇒ 取回用 `git show 73f4d6b:fuzzy_scripts_720/tmp/c010_alt_syntax_gate_tmp.tsv | md5 -q` = `6d4dc390…`，与登记的第二轮表 md5 逐字节一致；复跑前仍以脚本 md5 自证代次。
- **v1→v2 两处修门**（v1 脚本 md5 `4009de13…`、v1 表 md5 `a8afda22…`，v1 数据列**禁止引用**）：① `tr '\n' '|'` 与列分隔符 `|` 冲突 ⇒ PHP CLI 的 Parse error 打两行，实测 `n_*` 行 **NF=9** 而表头声明 7 列（`p_*` 行 NF=7）⇒ 改为字面量 `\n` 连接；② compile_fail 支只写 `<compile_fail>` 且随后 `rm` 掉 `.clog` ⇒ **AOT 自己的报错原文不在表内**，本门最需要的证据丢失 ⇒ 新增 `normlog`（剥 `Error: `、`on line N`→`LINE`、`/tmp/…`→`TMPDIR`）写入 aot 列。
- **跨 run 自证**：修门后 23 行的 `(shape, php_rc, aot_rc, verdict)` 四列与 v1 **逐行全等**（`diff` 空 ⇒ `V1V2_KEYCOLS_IDENTICAL=23/23`）⇒ 修门未扰动判据。
- 注册读数（v2 全量，`SMOKE_ONLY=0`）：`C010J_DONE shapes=23 same=16 diff=0 over_accept=5 both_reject=2 aot_only_red=0 run_red=0 both_err_diff=0 repo_build_residue=0`，`ELAPSED=77s`。
- `ONLY=` 冒烟通道写入**独立** `c010_alt_syntax_smoke_tmp.tsv`（本轮三形冒烟 8s 验证判据后已删）。

**正例面 = 16/16 SAME ⇒ 「替代语法已支持」定案**：`p_if`(A) / `p_if_else`(B) / `p_if_elseif_else`(C) / `p_if_elseif_mid`(B，中间臂) / `p_while`(012) / `p_for`(012) / `p_foreach`(123) / `p_foreach_kv`(`a=1;b=2;`) / `p_switch_case`(two) / `p_switch_default`(dflt) / `p_nested_if_foreach`(G) / `p_alt_in_block`(K，替代语法嵌在 `{}` 内) / `p_fn_return_alt`(R，函数体内 `return` 走 endif) / `p_break_in_alt_while`(X) / `p_alt_multi_stmt`(6，替代嵌替代) / `p_alt_top_and_tail`(`Z!`，尾部裸语句)。⇒ **`aot_only_red=0`、`diff=0`、`run_red=0`**：无任何「PHP 能跑而 AOT 拒绝/错值」的形 ⇒ 本面**不是**功能缺口。

**负例面 = 5 枚 OVER_ACCEPT + 2 枚 BOTH_REJECT，分界恰为软硬不对称（逐形到行）**

| 形 | PHP | AOT 实测 | 机制锚点（本代次复验） |
|---|---|---|---|
| `n_if_no_endif` `if (1 > 0): echo "P";` | rc=255 `unexpected end of file, expecting "elseif" or "else" or "endif"` | rc=0，输出 `P` | `:1594` EOF 静默收尾 + `:1515-1517` 软消耗 ⇒ **两处都无错误支** |
| `n_switch_no_endswitch` | rc=255 `expecting "endswitch" or "case" or "default"` | rc=0，输出 `S` | `:3556-3558` 跳过意外 token + `:3563-3565` 软消耗 |
| `n_mismatch_end` `if (1): echo "T"; endwhile;` | rc=255 `unexpected token "endwhile"` | rc=0，输出 `T` | `:1594` 循环条件**只认同种 end 标记** ⇒ `endwhile` 不终止 if 体，落到 `:482`→`:3299-3305` 被吃成 `.variable`，随后 EOF ⇒ 三重宽容叠加 |
| `n_double_endif` | rc=255 `unexpected token "endif", expecting end of file` | rc=0，输出 `V` | 首个 `endif` 于 `:1515` 消耗；**第二枚**走 `:482`→`:2428` 软分号→`:3300` 关键字当标识符 |
| `n_endif_alone` 顶层裸 `endif;` | rc=255 `unexpected token "endif"` | rc=0，**空输出** | 同上 `:482`/`:2428`/`:3300` ⇒ 生成**零指令**的变量表达式（§3.1 A 类同机制，此处由旗标容忍支而非查表落空触发） |
| `n_while_no_endwhile` | rc=255 | **两侧同拒**（产物不可执行） | `:1581` 硬 `eat` ⇒ AOT 原文 `syntax error, unexpected end of file, expecting token on line LINE` |
| `n_colon_brace_mix` `if (1) { echo "U"; endif;` | rc=255 `unexpected token "endif"` | **两侧同拒** | 首错在 `parseBlock`（`:2439-2442`）：`endif` 于块内被 `:3300` 当变量吞掉 → 软分号 `:2428` → EOF → `:2442 eat(.r_brace)` 硬报错，AOT 原文 `unexpected end of file, expecting "}" on line LINE` ⇒ **两侧最终都拒，但报错点不同**（v1 表无法自证，v2 的 `aot_log=` 列才暴露） |

⇒ 与 §3.5 的「瞎词 over_accept=14」**同源但不同面孔**：H2 测的是**任意标识符**能否占关键字位，本门测的是**替代语法自身**的接受/拒绝边界；两者共同指向同一结构缺陷＝**关闭标记的消耗软硬不一致**（`if`/`switch` 软、`while`/`for`/`foreach` 硬），且 `:3299-3305` 的旗标容忍支把「异种/多余 `end*`」也降级成了普通变量语句。

**反向收口 §3.5 的两枚旧形**：H2 的 `n_endif`（`if (1 > 0): echo "endif_ok"; Zkwhq;`）与 `n_endswitch` 其实就是「**替代语法开口头 + 假关闭标记**」，当时只能记为「该文法位对任意标识符宽容」；本门给出完整链条（`:1594` 体扫描遇异种标记不终止 → `:482`/`:3300` 把瞎词吃成变量语句 → `:1515`/`:3563` 软消耗在 EOF 处静默通过）⇒ §3.5 判读表 `n_endif` 行「终止位不校验」的旧措辞**升级为已解释机制**，两形不再需要独立假设。

**附带发现（消息质量，非本单根因）**：`tagToExpected:220-235` 实测**无任何 `.k_*` 臂**，兜底 `else => "token"`（`:235`）⇒ 硬 `eat(.k_endwhile)` 报的是 `expecting token`，而 PHP 报 `expecting "endwhile"`。属错误消息面，P2 登记。

**语料面（PHP 官方 `token_get_all` 分词器实测，资产 `fuzzy_scripts_720/tmp/c010j_alt_corpus_scan_tmp.php` md5 `40d8d591ac4c3c0e1ee69b71a53aedaf`；判据 3/4）**

| 语料 | 文件数 | 替代语法**开口头** | 关闭标记 token（语法位） | 花括号头 |
|---|---|---|---|---|
| `fuzzy_scripts_720/pass/`（冻结基线） | 68 | **0** | **0** | 697 |
| `fuzzy_scripts_720/fail_runtime/` | 77 | **0** | **0** | 959 |
| `fuzzy_scripts_720/fail_compile/` | 12 | **0** | **0** | 259 |
| `fuzzy_scripts/`（旧语料，非基线） | 42 | **5** | **5** | 140 |
| `fuzzy_scripts_715/` | 50 | 0 | 0 | 746 |

- 粗筛 `grep -E '\b(endif|endwhile|endfor|endforeach|endswitch)\b'` 在 720 全树命中 **32 行 / 3 文件**，分词器逐行判读 ⇒ **全部位于字符串字面量或注释内**（模板 DSL 文本 `{% endif %}`、`parseUntil($tokens, ['endif','else'])`、`// skip endif`）⇒ **语法位 0**，与本表一致。
- **开口头与关闭标记在两处独立计数上必须成对**（720 三目录 0/0、`fuzzy_scripts` 5/5）⇒ 该对称性同时**自证扫描器**（旧语料 5 枚 = `for`×2、`while`×2、`foreach`×1，行号 `:46/:53`、`:16/:92`、`:37`，与 v1 扫描器漏跳空白时的 `alt_syntax_headers=0` 读数是**同一脚本两版**，v1 结果作废）。
- ⇒ 结论按判据 4 拆分：**「语料内」暴露面 = 0**（冻结基线对本面零保护力，正例/负例都不会被官方回归抓到）；**「机制可达」= 完全可达**（任何用 `endif;` 风格书写的现网脚本即命中正例面，写错闭合即命中 OVER_ACCEPT 面）。

**语料外交叉实测（真实脚本，非最小探针，2026-10-08）**：`fuzzy_scripts/test_006_loops_for.php` / `test_007_loops_while.php` / `test_008_loops_foreach.php`（含上述 5 枚替代语法构造）逐枚 `--compile --no-debug-info` + 运行，与 `/opt/homebrew/bin/php` 真值 `diff` ⇒ **3/3 SAME**（输出行数 40 / 37 / 43，`php_rc=0 aot_rc=0`，`residue=0`）⇒ 正例面在**大脚本真实语境**（循环变量、多轮迭代、键值 foreach）下同样成立，不只是 16 枚最小形。

**跨 run 复证（第二轮，2026-10-08，本会话）**：同代次四枚 md5 全等（`compiler_md5=5beb1591018e6092ffc0ab0446344eee`、`lexer_md5=e3dd4191a1c3dfdf816b5873b4c60e5f`、`keyword_lookup_md5=ef70993a7caac6deb9b2e5a23bf7d143`、`parser_md5=e3987a361d1db45bc3eadefc7afa249e`）⇒ 门 J 汇总列与首轮登记**逐项等值**：`shapes=23 same=16 diff=0 over_accept=5 both_reject=2 aot_only_red=0 run_red=0 both_err_diff=0 repo_build_residue=0`。逐形表的等值用 **md5 决定性校验**取证（不靠人工比对）：本轮表 md5 `6d4dc390aef69c916ed1fa171b5f8aaa`，把唯一变动行 `ELAPSED=76s` 归一回 `77s` 后 md5 **= 登记值 `8b208dd0b9123c5f6bc8ee306cda5360`** ⇒ **33 行（含 8 行表头 + 23 形数据 + 耗时 + 汇总）除耗时行外逐字节全等**，5 枚 `OVER_ACCEPT` 的 `php_norm`/`aot_log` 双列原文亦逐字符一致。真实语料 3 枚复跑 ⇒ 行数 **40 / 37 / 43** 全等且 `cmp` 逐字节 SAME。⇒ **本门已可作守卫门使用**（两枚硬守卫列 `aot_only_red`、`run_red` 两轮均为 0，任何转正即真回归）。

**行号口径澄清（防后续会话误判漂移）**：上表「旧语料 5 枚」行号 `:46/:53`、`:16/:92`、`:37` 是**开口头**（`for (…):` / `while (…):` / `foreach (…):`）行号，与 §3.6 表格列名「替代语法**开口头**」一致；实测**闭合标记**行号为 `:48/:55`、`:19/:94`、`:39`。两列**不同物、非漂移**，复测时须分别 grep 两类锚点。

**三条结论**：
1. **§7-15 的「不可判」已闭环，且判为「真支持」**：正例 16/16 + 真实语料 3/3 逐字节等值，`aot_only_red=0`。
2. **代价是新立一张面孔**：**5 形过度接受**＝AOT 接受 PHP 拒绝的替代语法错写，且**静默**（`echo` 臂照常执行或整形空输出，无 warning）⇒ 与本单 §4「静默性」同族，属**解析层宽容**而非发射层缺陷。
3. **本门与 H2 都属「未受基线保护」面**（语料 0）⇒ 官方十二腿门链对本家族零暴露，纳入与否仍是 D-7。

**修复建议（落地前登记，2026-10-08；未动源码 ⇒ 成本列当时为「未实测」。实际落地形态与实测见下方「R-3 批落地实测」）**

| 优先级 | 影响面 | 落地成本 |
|---|---|---|
| **P1** 把 `:1515-1517`（`endif`）与 `:3563-3565`（`endswitch`）的软消耗改为**硬 `eat`**，与 `:1581`/`:1672`/`:1833` 对齐 ⇒ 一次消 5 枚 OVER_ACCEPT 中的 2 枚根因面并让另 3 枚报错点后移到明确位置 | 仅 parser 错误路径；正例面（16 形 + 真实语料 3 枚）零影响，因它们本就走完整闭合；**风险 = 现网"缺闭合"脚本从静默错输出变编译期报错**（即 §七-1 意义上更正确） | **实测**：门 J v3 `70s`/29 形 + 真实语料 3 枚复跑 + 六门 `E/F/G` 等值复跑（主回归/影子另计）。**「必须与改动 2 同批」＝读码推导，未做单臂反证**（旧代码 `parseElseifAlternative` 用 `parseStatement()` 只取一条语句 ⇒ 硬 `eat` 会在臂内第二条语句处见到非 `endif` 而报错）；实测侧只证明「同批后 `p_if_elseif_multi`/`p_if_else_multi`/`p_if_elseif_chain_multi` 三枚 SAME」 |
| **P1** `:1594` 体扫描补「异种 `end*` 即终止并报 unexpected」 | 消 `n_mismatch_end`/`n_double_endif`/`n_endif_alone` 三枚的直接入口 | **实测**：落地为 `:1627` 的 `isAlternativeCloserTag` 停止条件 + `:3333` 把五枚 `end*` 排除出表达式主位容忍支，三枚形均转 `BOTH_REJECT`。**「只做前者不彻底」＝读码推导**（`:3333` 的容忍支仍会把 `endif` 接成 `.variable` ⇒ 推断会静默），**未单独回滚 `:3333` 复测** ⇒ 若要定该反证需另开一臂 |
| **P2** `tagToExpected:220-235` 补 `.k_*` 臂（至少 5 枚 `end*`），使消息与 PHP 对齐（`expecting "endwhile"`） | 纯错误消息面，语义零影响 | **已实测**：补臂后 10 枚同拒形里 **6 枚**消息与 PHP 同词族，**4 枚**仍走通用句 `Unexpected token in expression`（另一条报错支）⇒ 消息面**部分**收口，残差见下方登记 |
| **P2** 维持现状 + 只把门 J 当**守卫门**（读数不得变化） | 零风险，但 5 枚宽容面长期存在 | **未采用**（老铁裁决为修） |

**R-3 批落地实测（2026-10-09，老铁裁决＝「A 旗标门控，只改 AOT」+「只做 CODEGEN-010 门 J P1」）**
> 批次号「R-3」＝本单第 3 个修复批次，**与 §5 的路线 `R-3`（发射期静默金丝雀）无关**（后者仍未启动）；消歧全文见 §5 开头「★ 编号消歧」。

代次戳：`parser.zig` md5 `5ad452fe4bc250b4732cbb3a2827b28a` / **4288 行**（落地前 `e3987a36…` / 4230 行）；`lexer.zig` `e3dd4191…`、`keyword_lookup.zig` `ef70993a…` **未动一行**；二进制 `zig-out/bin/php-interpreter` md5 `81f8a55a989f9a793fec2f75c32fd37d`（`timeout 600 zig build` → `rc=0`）。

改动面 = **一枚旗标 + 七处判定**，全部只在 `strict_alt_closers == true` 时生效（新→旧锚点，旧行号即本小节前文表格的读码锚点）：

| # | 位置（新代次） | 落地前 | 落地后 |
|---|---|---|---|
| 0 | 旗标声明 `:32`、置位点 `:75`（`initWithModeInsensitive` 内，**在 `initFromLexer` 预取 curr/peek 之后**） | 无 | `strict_alt_closers: bool = false` ⇒ 只有 AOT 入口为 true |
| 1 | `if` 闭合 `:1533-1537`（旧 `:1515-1517`） | 软消耗 `if (curr == .k_endif) { nextToken(); eat(.semicolon) }` | `_ = try self.eat(.k_endif); _ = try self.eat(.semicolon)` |
| 2 | `elseif` 臂 then `:1561`、else 臂 `:1574`（旧 `:1540`/`:1549` 用 `parseStatement()`） | 单语句臂 ⇒ **读码推导**：与硬 `eat` 组合会误拒 PHP 合法的多语句臂（未做单臂反证） | 旗标开启时改走 `parseAlternativeBody(.k_endif)`（多语句扫到闭合位）；实测覆盖 = 三枚多语句臂形 SAME |
| 3 | 体扫描 `:1627`（旧 `:1594` 循环条件） | 只认同种 `end_tag` ⇒ 异种 `endwhile` 被当普通语句吞掉 | `if (strict_alt_closers and isAlternativeCloserTag(curr)) break` ⇒ 停在闭合位由调用侧硬 `eat` 报错 |
| 4 | 表达式主位 `:3333`（旧 `:3299-3305` R-2 甲批容忍支） | 旗标开启时 `end*` 可降级成 `.variable` ⇒ 裸 `endif;`／`endif; endif;` 生成**零指令**语句而静默通过 | 五枚关闭标记**排除出容忍支** ⇒ 落回 `eat` 报错路径 |
| 5 | `switch` 意外 token `:3595`（旧 `:3556-3558`）＋闭合 `:3603-3607`（旧 `:3563-3565`） | 整枚跳过 + 软消耗 | 仅在 `is_alternative` 时 `break`（花括号支行为不变）＋ `eat(.k_endswitch)`/`eat(.semicolon)` |
| 6 | 集合助手 `:3976` | 复用 `isAotExtendedKeywordIdentifierTag`（**6 枚含 `.k_struct`**） | 新建 `isAlternativeCloserTag`＝**恰好 5 枚**，覆盖面独立、不收窄不扩 |
| 7 | 消息面 `:245-249`（旧 `tagToExpected:220-235` 无任何 `.k_*` 臂） | 兜底 `else => "token"` ⇒ 报 `expecting token` | 补 5 枚 `end*` 臂 ⇒ 报 `expecting "endif"` / `"endwhile"` / `"endswitch"`（纯消息，不改接受/拒绝判定） |

**门 J v3 全量读数（29 形，`SMOKE_ONLY=0`，`ELAPSED=70s` = **2.4 s/形**）**：
```
C010J_DONE shapes=29 same=19 diff=0 over_accept=0 both_reject=10 aot_only_red=0 run_red=0 both_err_diff=0 repo_build_residue=0
```
- **对照本小节前文的登记预测**：`over_accept 5→0` **达成**；`same` 旧 16 枚**全部仍 SAME**（新增 3 枚多语句臂正例也 SAME ⇒ `same=19`）；`both_reject` 预测 `2→7` 是**按 23 形口径**给的，v3 实际 10 形＝旧 7 + 新增 3 枚负例，逐形对照无缺一枚；两枚硬守卫列 `aot_only_red=0`、`run_red=0` ⇒ **零真回归**。
- **预测偏差的根因（登记为口径教训，不是门坏）**：预测写「`same=16` 不变」时假定「正例面本就单语句臂」，而 `parseElseifAlternative` 用的是 `parseStatement()`（**读码推导**：只取一条语句 ⇒ 硬 `eat` 会在臂内第二条语句处报错；**未做单臂反证实测**）⇒ 照预测只改硬 `eat`，`if (0): … elseif (1): $s=1; $s+=2; …` 这类 PHP 合法写法**推断**会转成 `AOT_ONLY_RED`。落地时把这三枚补进门（改动 2 的验收位），实测 3/3 SAME ⇒ **本门的正例面必须含多语句臂形才算守住改动 2**，旧 16 形对改动 2 零保护力。
- **改动 5 的落地前置实测**（`case` 前裸语句，四形含花括号对照）：PHP 全部 `Parse error … expecting "endswitch" or "case" or "default"` ⇒ 新增的 `break` 与 PHP 同向，非新造拒绝；`n_switch_stmt_before_case_alt` 实测 `BOTH_REJECT`。
- **消息面残差（P2 未收口）**：10 枚 `BOTH_REJECT` 里 **6 枚** AOT 原文与 PHP 同词族（`unexpected end of file, expecting "endif"`／`expecting "endwhile"`／`expecting "endswitch"`／`unexpected token "endwhile", expecting "endif"`／`unexpected token "echo", expecting "endswitch"`），另 **4 枚**（`n_endif_alone`、`n_colon_brace_mix`、`n_double_endif`、`n_else_no_endif`）仍是通用句 `Unexpected token in expression` ⇒ 走的是另一条报错支、不经 `tagToExpected`。**本门判据只比接受/拒绝边界**（与 H2 同源），消息措辞不入判据。

**真实语料复跑（新代次，非最小探针）**：`fuzzy_scripts/test_006_loops_for.php` / `test_007_loops_while.php` / `test_008_loops_foreach.php` 逐枚 `--compile --no-debug-info --output=/tmp/aot_compile_*` + 运行 ⇒ **3/3 `cmp` 逐字节 SAME**，行数 **40 / 37 / 43** 全等、`php_rc=0 aot_rc=0`，产物与临时目录已删、`git status` 语料目录净空 ⇒ 正例面（含 5 枚替代语法构造的大脚本）在严格档下零误拒。

**分叉的源码级取证（D-2 裁决口径的硬证据，`grep` 全仓 `Parser.init*`）**：置位点只有 `initWithModeInsensitive`（`:70-77`），而它的调用点只有 **2 枚且都是 AOT 入口** —— `src/main.zig:726`（单文件 AOT）与 `src/aot/multi_file_compiler.zig:203`（多文件 AOT）。其余 5 枚构造点 **旗标恒为 `false`** ⇒ 逐字节等价于落地前：`src/main.zig:508`（`initWithMode`，tree/bytecode/fast 解释执行）、`src/runtime/vm.zig:1441`、`src/runtime/vm.zig:9576`、`src/compiler/root.zig:133`（`Parser.init`，只被 `src/aot/test_control_flow_ir.zig:64` 与 root 内部 `:179` 用）、`initWithModeAndHooks`（全仓零调用）。`src/aot/compiler.zig:906` 只接收外部 AST，不自建 Parser。

**六门在新代次的复跑（链 `fuzzy_scripts_720/tmp/c010_r3_acceptance_chain_tmp.sh`，六门 → 主回归 → 影子）**：门 E/F/G 已实测且与登记值**逐项等值**（表头 `compiler_md5=81f8a55a…`）：
```
门 E：C010KW_DONE shapes=19 same=19 diff=0 silent_empty=0 aot_fatal=0 compile_fail=0
门 F：C010MECH_DONE shapes=8 same=8 diff=0 zero_instr=0 compile_fail=0
门 G：C010G_DONE  shapes=7 same=7 diff=0 red_confirmed=0 guard_same=4 guard_red=0 compile_fail=0
```
**门 H / H2 / I 在新代次的实测（同链 `[1/3]` 阶段 09:53:24 → 10:09:42 = **16 分 18 秒**，六门含 E/F/G）**：

| 门 | 新代次读数（表头 `compiler_md5=81f8a55a…`） | 与注册值对照 | 逐行取证 | `ELAPSED`（本轮 / 上一轮同代脚本） |
|---|---|---|---|---|
| E | `shapes=19 same=19 diff=0 silent_empty=0 aot_fatal=0 compile_fail=0` | 逐项等值 | 19 行 `diff_rows=0` | 69s / 68s |
| F | `shapes=8 same=8 diff=0 zero_instr=0 compile_fail=0` | 逐项等值 | 8 行 `diff_rows=0` | （同链） |
| G | `shapes=7 same=7 diff=0 red_confirmed=0 guard_same=4 guard_red=0 compile_fail=0` | 逐项等值 | 7 行 `diff_rows=0` | （同链） |
| H | `shapes=79 arms=200 face=0 noface=78 confounded=1 bad_probe=0 ctrl_compile_fail=0 probe_compile_fail=0 probe_timeout=0 inverse_shapes=21 inverse_face=0 inverse_noface=21 inverse_confounded=0 repo_build_residue=0` | **逐项等值**（R-2 落地后的 face=0 面未被动摇） | 103 数据行 `diff_rows=0`（排除 4 表头行与 `ELAPSED`）⇒ **逐字节等值** | 738s / 721s（注册首轮 595s） |
| H2 | `shapes=15 over_accept=12 strict_same=1 aot_compile_fail=2 php_ok_aot_diff=0 repo_build_residue=0` | `over_accept` **14→12**、`aot_compile_fail` **0→2**（唯一变动列） | 13 行等值、**2 行按预期改写**（见下） | 46s / 53s |
| I | `shapes=19 tree_same=7 tree_diff=12 bc_same=7 bc_diff=12 aot_same=19 aot_diff=0 aot_compile_fail=0 both_red=0 vm_only_red=12 aot_only_red=0 repo_build_residue=0` | **逐项等值** ⇒ **分叉判据达成**：`tree`/`bc` 四列与冻结注册值一致且 `aot_same=19`，VM 侧 12 枚红面按 D-2 裁决保留现状 | 19 行 `diff_rows=0`（每行含三模式输出列）⇒ 解释器/字节码侧**逐字节未动** | 69s / 68s |

- **门 H2 的两列变动 = 收敛，不是回归（已逐形定位）**：变动行为 `n_endif`、`n_endswitch` 两形，探针体为 `if (1 > 0): echo "endif_ok"; Zkwhq;` / `switch (1): case 1: echo "s"; break; Zkwhq;`（瞎词 `Zkwhq` 占在**关闭标记位**，脚本 `:45-46`）。两形 **PHP 均 `php_rc=255`**（`expecting "elseif" or "else" or "endif"` / `expecting "endswitch" or "case" or "default"`），落地前 AOT **rc=0 且照打 `endif_ok`/`s`** ⇒ 旧读数为 `OVER_ACCEPT`；落地后旗标开启使闭合位改硬 `eat`，AOT 在**解析期即报错、无产物**（`--compile` 仍 rc=0 ⇒ 按规则 21 以产物存在性判，记为 `AOT_COMPILE_FAIL`）。⇒ **`over_accept` 净减 2 枚与门 J 的 `over_accept 5→0` 同源**，是宽容面继续收窄；`aot_compile_fail` 桶在本门的历史语义是「潜在红」，此处实为「与 PHP 同拒」。
- **上述两形的直接复测（新代次二进制，逐字原文，产物已删、临时目录净空）**：
  ```
  if (1 > 0): echo "endif_ok"; Zkwhq;
    PHP: Parse error: syntax error, unexpected end of file, expecting "elseif" or "else" or "endif" on line 3
    AOT: Error: Parse error: syntax error, unexpected end of file, expecting "endif" on line 3   ⇒ 无产物（真拒）
  switch (1): case 1: echo "s"; break; Zkwhq;
    PHP: Parse error: syntax error, unexpected end of file, expecting "endswitch" or "case" or "default" on line 3
    AOT: Error: Parse error: syntax error, unexpected end of file, expecting "endswitch" on line 3 ⇒ 无产物（真拒）
  ```
  ⇒ 同时**实证改动 7（`tagToExpected` 五枚 `end*` 臂，`:245-249`）在真实报错面可见**：AOT 已报出词族正确的 `expecting "endif"` / `expecting "endswitch"`（旧兜底为 `expecting token`），与 PHP 同词族、只差 PHP 附带的并列词。
- **门口径局限（登记，下轮引用勿误判）**：门 H2 的汇总列**没有 `BOTH_REJECT` 桶**（建门时 15 形全为「PHP 拒 / AOT 收」，未预见到两侧同拒）⇒ **本轮起 `aot_compile_fail>0` 必须回读逐形列的 `php_rc` 才能判向**：`php_rc=255` ⇒ 同拒（收敛方向）；`php_rc=0` ⇒ 真回归。守卫列 `php_ok_aot_diff=0`、`repo_build_residue=0` 本轮仍为 0 ⇒ **本轮无任何「PHP 能跑而 AOT 变红」**。
- **对既有 P1 建议的部分收口（本轮的额外收益）**：R-2 时代 §3.4.6 把 H2 读作「`over_accept=14` **不变** ⇒ 瞎词臂不受影响」，交接文档据此立了 P1「H2 面收口：文法位过度宽容」。**本轮实测推翻「不受影响」的适用范围**：14 枚中有 **2 枚**（`n_endif`/`n_endswitch`＝**关闭标记位**）随 R-3 收敛，⇒ 该 P1 面从 14 枚**收窄为 12 枚**（`n_do`/`n_else`/`n_void`/`n_const`/`n_final`/`n_mixed`/`n_public`/`n_global`/`n_object`/`n_private`/`n_finally`/`n_namespace`＝类型位、修饰符位、声明关键字位），**其余 12 枚与替代语法无关、仍待单独裁决**，本批未触碰。
- **主回归（官方 `fuzzy_scripts_720/run_regression.sh`，`[2/3]` 阶段 10:09:42 → 10:23:32 = 13 分 50 秒）**：`Total=68 / Pass=67 / Fail(Compile)=0 / Fail(Runtime)=0 / Fail(Diff)=0 / Skip=1`，唯一非 PASS 仍为 `f004_oop_deep_inheritance_magic.php SKIP PHP_error_exit=255` ⇒ **与 R-2 注册基线逐项相同，基线保持**。报表逐字取自 `fuzzy_scripts_720/regression_report.md`（测试时间行 `2026-10-09 10:23:32`）。
  - 对照口径更正（登记）：同目录 `regression_failures.tsv` 在上一轮快照里**只有 20 行**（19 PASS + 1 SKIP，非 68 行全表）⇒ **不可用作逐行等值对照**，等值判据取报表的六个计数器；本轮该表为 **68 行 = 67 PASS + 1 SKIP**（`cut -d'|' -f1 | uniq -c` 实测）。
- **影子门（`c010_shadow_main_md5_tmp.sh`，`[3/3]` 阶段 10:23:32 → 10:49:57 = 26 分 25 秒）**：`C010_SHADOW_DONE total=68 same=68 diff=0 miss=0 ELAPSED=1585s` ⇒ **冻结基线（修复前二进制 `1f15e4ce…`，`/tmp/c010_prefix_backup/`）零漂移**，68 语料的生成码 `main.zig` 逐形 md5 与新代次全等 ⇒ 本批在语料面上**实测发射中性**（跨 R-2 + R-3 两批的累计自证）。中途只读到 49 对时的部分读数已为 `DIFF=0`、`NO_MAINDIR=0`。
- **门 D8（§8 独立缺陷家族验收面）在新代次的补测**：本链未把 D8 排进去，故链毕后单独补跑。
  - **首轮（10:31 前后，与影子门**并发**执行）读数 `… repo_build_residue=1 … ELAPSED=51s` ⇒ 禁止引用**：D8 的 residue 列判据是 `ls -d .zigphp_aot_build_* aot_compile_*`（脚本 `:90`），而影子门在 `ZIGPHP_AOT_KEEP_TEMP=1` 下每形抽取生成码后才 `rm -rf "$tdir"`（脚本 `:36`）⇒ 并发窗口里仓库根必有该目录，属**门自身与被测物无关的并发污染**。
  - **复跑（10:50，串行无并发）**：`C010D8_DONE shapes=14 defect_red=1 guard_same=13 compile_fail=0 bad_probe=0 repo_build_residue=0 SMOKE_ONLY=0 ELAPSED=49s`，逐行与上一代次快照 `diff` **零差异** ⇒ 与注册值（修复代 #122c `defect_red=1 guard_same=13 … 48s`）**逐项等值**，唯余 `d3a`=goto 发射侧子轮。**教训登记：任何带 `repo_build_residue` 列的门都不得与影子/回归类长时间门并发执行。**
- **整条链实测耗时**：09:53:24 → 10:49:57 = **56 分 33 秒**（六门 16m18s + 主回归 13m50s + 影子 26m25s）；加 D8 补测两轮 ≈ 100 秒 ⇒ **本轮验收总成本 ≈ 58 分钟**，零源码改动。

**`zig build test` 的既有噪声（不在本单，登记以免下轮误判为回归）**：`timeout 900 zig build test` **RC=0**，但日志固定尾行 `failed command: ./.zig-cache/o/55e298300f7347fe4f670dbeb02073ec/test`。已归因为与解析器无关的 CI 门面试验（该产物 mtime `Oct 5 08:55`，早于本轮；直接跑 `./.zig-cache/o/55e29…/test` ⇒ `All 3 tests passed`，3/3 OK，其 `CIRunner` 用例向 stdout 打性能报告）。⇒ **复跑必现同一路径尾行，非本轮新增**。

---

### 3.7 任务 #126 取证轮：**永久侧门 K**（花括号 `switch` 与 `case` 臂族）v1 实测 ⇒ §7-15c 由 1 形扩到 **4 形**，并新立**两张独立面孔**（零 `src/` 改动，2026-10-09）

**建门动因**：§7-15c 只登记了 **1 枚**形（`switch (1) { echo "W"; }`），且「`is_alternative` 门控可保证对 68 语料的花括号 `switch` 零扰动」这一句属**未实测推断**。本轮把它取证到「面孔穷举 + 语料面穷举」，形为**新门文件**（门 J v3 已注册 ⇒ 禁扩已注册门，见记忆口径「new shapes ⇒ new gate file」）。

**代次锚点（一条命令同抓四戳，脚本定稿后取值）**：

| 资产 | md5 | 备注 |
|---|---|---|
| `fuzzy_scripts_720/tmp/c010_brace_switch_gate_tmp.sh` | `6408a6b6f32d73367fa8e458a8ee249b` | 门 K v1，24 形，脚本 mtime **早于**表 mtime |
| `fuzzy_scripts_720/tmp/c010_brace_switch_tmp.tsv` | `b3eb6e913edbc774a8b95a3fe61f0613` | 注册读数表（第二轮全量跑） |
| `…/c010k_presnap/c010_brace_switch_gen1_tmp.tsv` | `6f4e9f8b2d119b8cb5c08f694cfbca7a` | 首轮快照；与注册表**仅 `ELAPSED` 一行不同**（43s／42s） |
| `…/c010k_brace_switch_corpus_scan_tmp.php` / `.txt` | `d7a2ccdc0a3002cacfe0d7c0cd858a04` / `a999224aba026cd5bf6096cf31d3e639` | 语料扫描器 ①（头型 / 语句头位） |
| `…/c010k_case_order_terminator_scan_tmp.php` / `.txt` | `83247654ada70c9b587181869753af66` / `653fc553cf255214fc0f50254ad2d628` | 语料扫描器 ②（default 位次 / 分号臂），**v2**（v1 读数全废，见下） |
| 二进制 / `parser.zig` | `81f8a55a…` / `5ad452fe…` | 与 §3.6 的 R-3 批**同代次** ⇒ 本轮零源码改动，读数可直接对接 R-3 终态 |
| `fuzzy_scripts_720/tmp/c010km_crossmode_probe_tmp.sh` / `.txt` | `973996ef88c6db340871dc9402682c42` / `52f32f9d0d71bf350e522f1b89ac8b5b` | **跨模式探针门 C010KM**（面 B／C 落地前置问询的取证件：6 形 × `php`/`--mode=tree`/`--mode=bytecode`/`AOT` 四侧，实测 `ELAPSED=13s`；把 `/private/tmp/c010km.XXXXXX` 路径归一后跨 run `diff_rows=0`）⇒ 读数与判读归 **AOT-CODEGEN-011 §2.3**，本节只引其「三模式三样错答」结论 |

**判据**：承 §3.5.1（任务 #125）定稿的**五桶契约**逐字同口径（`SAME_BOTH_ERROR_LIKE` / `OVER_ACCEPT` / `DIFF_PHP_OK_AOT_DIFF` / `BOTH_REJECT`=收敛 / `AOT_ONLY_RED_COMPILE`+`AOT_ONLY_RED_RUN`=硬守卫），编译失败以**产物可执行性**判（规则 21）。

**门 K v1 注册读数（24 形 = 正例 14 + 负例 10，`ELAPSED=42s` ⇒ 1.8 s/形，本单最便宜的门）**：

```
C010K_DONE shapes=24 same=8 over_accept=4 diff_php_ok=1 both_reject=6 aot_only_red=5 run_red=0 repo_build_residue=0 SMOKE_ONLY=0
```

> **【2026-10-09 任务 #127 就地更正】** 上块是**面孔 A 落地前**（R-3 代次 `81f8a55a…`）的历史注册读数。R-5 落地后门 K 的**活跃表已同地覆写**：注册副本逐字节存于 `fuzzy_scripts_720/tmp/c010_r5_presnap/c010_brace_switch_tmp.tsv`（md5 `b3eb6e91…` 不变），当代读数 = `same=8 over_accept=0 diff_php_ok=1 both_reject=10 aot_only_red=5 run_red=0`（`ELAPSED=31s` = **1.3 s/形**）。引用口径：① `over_accept=0` 是**修复达成**、不是门坏掉；② `aot_only_red` **必须恒 = 5**（面 B 的 5 枚假拒绝属 AOT-CODEGEN-011，本批零触碰 ⇒ 该列若变动即为面 A 的改动外溢，须停手归因）；③ `diff_php_ok` **必须恒 = 1**（面 C 的 `k_default_first`）⇒ 逐形前后对照见 §3.8.4。

**跨 run 复证**：注册表与首轮快照去掉 `ELAPSED` 行后 `diff` ⇒ **`diff_rows=0`**（24 形数据行 + 7 行表头逐字节全等）。
★ **本门自建成起就不是「守卫门」**：硬守卫列 `aot_only_red=5` **非 0** ⇒ 它是**验收门**（有已知红面），引用时禁止把该列读成「本轮新增回归」。

**三张面孔（实测到行）**

| 面孔 | 形（门 K 内 id） | PHP 真值 | AOT 实测 | 机制锚点（实文核对） | 归属 |
|---|---|---|---|---|---|
| **A（§7-15c 本体，宽容面）** | `k_stmt_before_case`、`k_stmt_before_case_two`、`k_nested_stmt_head`、`k_stray_endswitch` = **4 枚 OVER_ACCEPT** | 全部 rc=255 `unexpected token "…", expecting "case" or "default" or "}"` | 全部 **rc=0**；前三枚**空输出**，`k_stray_endswitch` 更**照跑并打 `z`**（`endswitch` 被当成意外 token 跳过后，`case 1:` 正常成臂） | `parser.zig:3592-3597` 的 `else` 支＝`if (is_alternative and self.strict_alt_closers) break;` ⇒ **花括号支保留** `self.nextToken(); // Skip unexpected tokens`，随后 `:3611 _ = try self.eat(.r_brace);` 仍成立 | **本单**（R-3 批的姊妹面 ⇒ §5 路线 **R-5**） |
| **B（新，反向面孔＝假拒绝）** | `k_case_semi`、`k_case_semi_fall`、`k_default_semi`、`k_case_semi_alt`、`k_case_semi_two_arms` = **5 枚 AOT_ONLY_RED_COMPILE** | PHP 8.5 仅 `Deprecated: Case statements followed by a semicolon (;) are deprecated, use a colon (:) instead`，**rc=0 且臂体照常执行**（`S`/`T`/`D`/`Q`/`b`） | **无产物**，AOT 原文一律 `Parse error: syntax error, unexpected ";", expecting ":"` | `parser.zig:3571`（`case` 臂）与 `:3583`（`default` 臂）= `_ = try self.eat(.colon); // or .fat_arrow` **硬只认冒号**；该处注释声称的「or .fat_arrow」实测**方向反了**（`case 1 => echo` PHP 自己 rc=255 ⇒ 见 `k_case_arrow` 形，实测 `BOTH_REJECT`） | ✅ **已另立 AOT-CODEGEN-011**（路线 **R-B1**，§五 裁决项 D-1 必答） |
| **C（新，语义面孔＝臂序丢失）** | `k_default_first` = **1 枚 DIFF_PHP_OK_AOT_DIFF**（PHP `DC` / AOT `D`） | 见下补充六形 | 见下补充六形 | `parser.zig:3616` 的 `.switch_stmt = .{ .expression, .cases, .default }` ⇒ **default 不在 `cases` 序列内 ⇒ 源码位次信息在 AST 层就没有**；IR 侧 `ir_generator.zig:3211-3221` 按 `case_blocks.items[i + 1]` 链 fall-through、末臂才 `:3215-3217` 接 `default_block`，default 体尾 `:3236-3237` **恒 `br merge_block`** ⇒ default 被强制搬到末臂位 | ✅ **已另立 AOT-CODEGEN-011**（路线 **R-C1**+**R-C2**，跨模式面 **R-C3** 待 §五） |

**面孔 C 的六枚补充实测（`/tmp` 一次性形，仓库根执行；与门 K 的 `k_default_first` 同代次同二进制）**

| 形 | PHP | AOT | 判读 |
|---|---|---|---|
| `switch (1) { default: echo "D"; case 2: echo "C"; }` | `DC` | `D` | default 体尾**不落进后续 case**（丢臂尾） |
| `switch (2) { default: echo "D"; case 2: echo "C"; }` | `C` | **`CD`** | 末位 case 的体尾**错落进 default** ⇒ 执行了 PHP 不执行的语句（**比丢尾更重**：假执行） |
| `switch (1) { case 1: echo "a"; default: echo "d"; case 2: echo "b"; }` | `adb` | `abd` | default 被搬到**末臂**位（臂序丢失的直接证据） |
| `switch (9) { case 1: "a"; default: "d"; case 2: "b"; }` | `db` | `d` | 未匹配走 default 后同样丢后续臂 |
| `switch (1) { case 1: "a"; case 2: "b"; default: "d"; }`（default 已在末） | `abd` | `abd` | **SAME ⇒ 控制臂**：default 位于末臂时全绿，正是 68 语料的唯一形态 |
| `switch (0) { case 1: "a"; default: "d"; case 2: "b"; case 3: "c"; }` | `dbc` | `d` | 多臂同形复现，非单臂特例 |

⇒ 面孔 C 的分界实测为「**default 是否位于末臂**」，与花括号／替代语法无关（替代语法侧同一 AST 结构同样受影响，但语料该族构造为 0，见 §3.6 语料面表）。

**跨模式补记（本轮新立探针门 `C010KM`，6 形 × `php`/`--mode=tree`/`--mode=bytecode`/AOT，实测 `ELAPSED=13s`，路径归一后跨 run `diff_rows=0`）**：上表六形中的四形（`k_default_first` 同码位形、`c_lastcase_fall_into_default`、`c_middle_default`、`c_ctl_default_last`）已进门固化，另两形（未匹配走的 `db/d`、多臂的 `dbc/d`）仍是一次性 AOT 侧形。三条判读（逐形读数与修复路线归 **AOT-CODEGEN-011 §2.3/§5**，此处只登记取证）：
1. **面 B 的修复点在三模式共享的 `parser.zig`** ⇒ 直改会让 tree/bytecode 从「**rc=0 零输出**」变成「真的执行」；AOT 侧反而至少留下了 `Parse error` 日志 ⇒ 是否一并改 VM 属 §五 问询项（011 的 D-1）。
2. **面 C 呈「三模式三样错答」**（`c_middle_default`：PHP `adb`／tree `ab`／bc `abd`／AOT `abd`）⇒ 根不在发射侧，而在 `ast.zig:186` 的形态缺字段；★★ **控制臂（default 已在末臂）在 tree 模式也是红的**（`ab` vs PHP `abd`，`vm.zig:10186` 的 default 支条件是 `if (!matched …)` ⇒ 解释器模式**永不 fall-through 进 default**）⇒ 冻结基线绿恰好只覆盖 AOT/bc 侧。
3. **副产品＝一张新流程面（非本单面孔）**：`--mode=tree`／`--mode=bytecode` **对解析失败静默吞掉**（rc=0、零输出、无错误行；另测缺 `}` 的 `if` 同现象）⇒ 任何只看 rc 的 VM 腿会把「编译失败」读成绿（承 §7-5 同族但更危险）。按 §五 **本轮只登记不修**。

**语料面穷举（两枚独立扫描器，`token_get_all` 分词器口径，判据 3/4）**

| 语料 | 文件 | switch 总数 | 花括号头 | 替代语法头 | 首 case 前有语句 | default 非末臂 | `case`/`default` 分号臂 | 冒号臂 |
|---|---|---|---|---|---|---|---|---|
| `fuzzy_scripts_720/pass/`（冻结基线） | 68 | 4 | 4 | 0 | **0** | **0** | **0** | 20 |
| `fuzzy_scripts_720/fail_runtime/` | 77 | 1 | 1 | 0 | 0 | 0 | 0 | 4 |
| `fuzzy_scripts_720/fail_compile/` | 12 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `fuzzy_scripts/`（旧语料，非基线） | 42 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `fuzzy_scripts_715/` | 50 | 2 | 2 | 0 | 0 | 0 | 0 | 13 |
| **GRAND** | 249 | **7** | **7** | **0** | **0** | **0** | **0** | **37** |

- **两枚扫描器的 switch/花括号头/替代头 三项独立计数逐项全等**（7／7／0）⇒ 互证（同 §3.6「开口头与关闭标记成对」的自证法）。
- 基线 4 枚花括号 `switch` 的站点已逐处回文核对 = `pass/f048:118`（default 末臂）、`pass/f134:94`、`pass/f134:160`、`pass/f163:133`（三枚**无 default**）＋ `fail_runtime/f082:98`（无 default）⇒ **三面孔的「语料内」暴露面全为 0**，冻结基线对它们**零保护力**；**「机制可达」= 完全可达**（写一个 default 不在末尾的 switch 即命中 C，用 `case 1;` 即命中 B，`switch` 首臂前塞一条语句即命中 A）。
- 面孔 A 的补充：语料里 `stmt_before_first_case=0` 意味着**合法代码永远不进入** `:3592` 的 `else` 支 ⇒ 「硬化该支对 68 语料发射中性」这一句由**推断升为实测**（但影子仍须跑，理由见下「落地成本」）。

**修 scanner 记录（先修 scanner、后引用；v1 读数全废，禁止引用）**：扫描器 ② v1 把**全树**的 `T_CASE`/`T_DEFAULT` 一律当 switch 臂，且终止边界只有 `:`/`;` ⇒ 两枚假阳性（enum 的 `case Hearts = 'v';`／`case Hearts;`，match 的 `default => "…"`）。v1 实测 `semi_terminator=87`（pass 20 + fail_runtime 46 + fail_compile 1 + 旧语料 3 + 715 17）**全部为这两族，switch 分号臂实为 0**。v2 改为「先算 switch 与 enum 的 token 区间、只落在 switch 区间内才分类；终止集扩 `:` `;` `=` `=>` `,`；臂序列只取本层深度」，并配**三枚必过控制臂**（`f048:15` match 不得记 SEMI、`f154:71` enum 带值 case 不得记 SEMI、合成形 `switch(1){case 1;}` 必须记 SEMI）＋ 一枚嵌套 switch 的过计控制臂（外层 default 末臂时不得记非末臂）。v1→v2 的**同输入合成控制**读数：`switch=10 / brace=8` 两代全等，`semi_arm 6→6`、`nonlast_default 4→3`（差的那枚正是 v2 修掉的过计）⇒ 修 scanner 只收窄假阳性。
**已知低估边界（明示）**：v2 的臂序列以花括号深度为界 ⇒ **替代语法体内嵌套的花括号 switch**、以及 `case` 后带花括号体（`case 1: { … }`）内的臂不计入外层，二者语料面均为 0。

**三条结论**：
1. **§7-15c 未收口面已量化**：花括号 `switch` 的宽容面 = **4 枚**（非 1 枚），其中 `k_stray_endswitch` 呈「**跳过关闭标记后照常执行**」的实质语义分歧，比空输出更重。
2. **同一段代码的另一方向也有面**：`case`/`default` 的**分号终结符**被 AOT **假拒绝** 5 枚（硬守卫列非 0）⇒ 「严格化」与「过度宽容」在 `parseSwitchStmt` 内**同时存在**，任何只盯 `OVER_ACCEPT` 列的评审会漏掉它（这正是 §3.5.1 五桶分向判据的价值）。
3. **面孔 C 与 A/B 不同根**：A/B 在 `parser.zig` 文法位，C 在 **AST 无臂序 + IR 按末臂链入**（`parser.zig:3616` × `ir_generator.zig:3211-3221/:3236-3237`）⇒ **不可并入 R-3 系列批**，且修复需动 `ir_generator.zig`（宪法 §一 超大文件，改前须 grep 既有模式）与 AST 形态 ⇒ **已另立 ✅ [AOT-CODEGEN-011](AOT-CODEGEN-011-switch-case-semicolon-terminator-and-default-arm-position.md)**（面孔 B = 路线 R-B1，面孔 C = R-C1+R-C2）。跨模式探针（C010KM）实测给该单新增两个必答问询项：**D-1**（面 B 落在三模式共享的前端 ⇒ 直改 vs 旗标门控只改 AOT）与 **D-3**（tree 侧连控制臂都红 ⇒ 是否一并修 VM/bytecode）。

**落地成本（实测口径，禁估算）**：门 K 本身 `42s`／24 形 = **1.8 s/形**；扫描器 ① `~2s`、② `~4s`（`timeout 90` 上限内）。面孔 A 的硬化 = ~~`:3595` 去掉 `is_alternative and`（**一行**）~~ **【该措辞已被任务 #127 实测否证，见 §3.8：直接去掉 `is_alternative and` 会把两枚 PHP 合法形新拒 ⇒ 实际形态＝旗标 + 单枚前导分号豁免支，共三处改动】**，面孔 B = `:3571`/`:3583` 两处 `eat(.colon)` 改「`:` 或 `;` 二者取其一」（**两行**）⇒ 二者均可沿用 §3.6 的既有验收链：**六门 16m18s + 主回归 13m50s + 影子 26m25s = 56m33s**（实测值，非估算）。面孔 C 无既有验收链可套（需 AST 形态先定），成本列「**未实测**」。

---

### 3.8 任务 #127 落地轮：**R-5（面孔 A 硬化）已落地并实测收口** + **永久侧门 L**（`switch` 臂表位邻形门，23 形）建成（2026-10-09）

**落地范围与裁决口径（先划界）**：老铁指令「继续推进已知问题修复」按已接受计划推进 ⇒ 本批**只落地面 A**，理由有二 —— ① 面 A 落在本单（根 = `parseSwitch` 的意外 token 跳过支）；② 修复形态沿用 §3.6 已验收的**旗标门控 AOT-only** 分叉 ⇒ 宪法 §五（不擅自改解释器/字节码）与 §六（非 AOT 逻辑调整须先问）均不越界。**面孔 B／C 属 [AOT-CODEGEN-011](AOT-CODEGEN-011-switch-case-semicolon-terminator-and-default-arm-position.md)，其 D-1…D-4 未裁决 ⇒ 本批零触碰**（门 K 的 `aot_only_red=5` 因此在本批前后**恒为 5**，不是「本批没修好」）。

#### 3.8.1 ★ 实测语法规则：**「一行」措辞被否证**（已在 §3.7「落地成本」就地标注）

`php 8.5.8` 直测得到的文法事实（决定 R-5 的最终形态，非推断）：

> **`switch` 的 case 列表位「恰好接受一枚空语句分号 `;`」**，花括号与替代语法皆然；第二枚分号、裸 `:`、裸 `{ }` 以及任何语句仍为 `php_rc=255`。

| 形（门 L id） | 源码 | PHP 实测 | 若照 §3.7 旧措辞「只去掉 `is_alternative and`」 |
|---|---|---|---|
| `l_semi_arm_list` | `switch (1) { ; case 1: echo "A"; break; }` | **rc=0**，输出 `A` | ✗ 新拒 ⇒ `AOT_ONLY_RED_COMPILE`（**今日绿形变红**） |
| `l_semi_only` | `switch (1) { ; }` | **rc=0**，空输出 | ✗ 同上 |
| `l_alt_semi_arm` | `switch (1): ; case 1: echo "A"; endswitch;` | **rc=0**，输出 `A` | ✗ 同上（且该形今日**已是红**，见 §3.8.5） |
| `l_two_semi_arm_list` | `switch (1) { ;; case 1: … }` | rc=255 `unexpected ";"` | ✓ 正确拒绝 |
| `l_alt_two_semi` | `switch (1): ;; case 1: … endswitch;` | rc=255 | ✓ 正确拒绝 |
| `l_semi_then_block` | `switch (1) { ; { } case 1: … }` | rc=255 `unexpected "{"` | ✓ 正确拒绝 |
| `l_bare_colon_arm_list` | `switch (1) { : case 1: … }` | rc=255 `unexpected ":"` | ✓ 正确拒绝 |

⇒ **实际落地形态 = 旗标 + 「单枚前导分号豁免」支**，共**三处**改动（§3.7 旧措辞「一行」作废）。守卫门 L 在落地**前**建成的全部价值就是先拿到这张真值表：若直接按「一行」落地，会把两枚今日绿的合法形打成硬守卫红，且消不掉 §3.8.5 的既有红。

#### 3.8.2 落地三处（`src/compiler/parser.zig`，`parseSwitch` 在 `:3555`）

| # | 位置 | 内容 | 为什么必须在此 |
|---|---|---|---|
| ① | `:33–38` | 新增字段 `strict_switch_case_list: bool = false;`（紧邻 R-3 的 `strict_alt_closers`） | 缺省 `false` ⇒ 解释器/字节码构造点逐字节等于历史（承 §3.6.4 的分叉口径） |
| ② | `:80–82` | `initWithModeInsensitive` 内 `p.strict_switch_case_list = true;`（与 `p.strict_alt_closers = true;` 同批） | 该旗标**只参与 parse 期判定**，curr/peek 已由 `initFromLexer`（`:41–58`）预取 ⇒ 构造后补设安全（与 `Lexer.case_insensitive_keywords` 必须在预取**前**置位形成对照，见 §3.4.6） |
| ③ | `parseSwitch` `:3572` + `:3601–3613` | 局部 `var case_list_empty_stmt = false;` + 在意外 token 的 `else` 支**之前**插入 `.semicolon and !case_list_empty_stmt` 豁免支，`else` 支改为 `if (self.strict_switch_case_list or (is_alternative and self.strict_alt_closers)) break;` | 豁免支实现 §3.8.1 的「只放行单枚」；`break` 后由 `:3628 _ = try self.eat(.r_brace);` / `:3620` 的 `endswitch` 硬 `eat` 报精确 `unexpected X, expecting "}"` |

```zig
// src/compiler/parser.zig:3601–3613（实测落地文本）
} else if (self.curr.tag == .semicolon and !case_list_empty_stmt) {
    // R-5 例外（门 L 实测，php 8.5.8）：case 列表首**恰好接受一枚空语句分号**——
    case_list_empty_stmt = true;
    self.nextToken();
} else {
    if (self.strict_switch_case_list or (is_alternative and self.strict_alt_closers)) break;
    self.nextToken(); // Skip unexpected tokens
}
```

**Zig 语言面记录（本轮踩到，登记为口径）**：`:3572` 的局部 `var` 上方注释**必须用 `//`**；写 `///` 触发 `expected statement, found 'a document comment'` ⇒ 首次 `zig build` 失败。doc comment 只能贴在声明式（字段/函数），不能贴局部变量。

**改动量实测**：`git diff --numstat src/compiler/parser.zig` ⇒ **81 插入 / 6 删除**（= R-3 批的 64/−6 + 本批净 **+17/−0**）；文件 `4305` 行。

#### 3.8.3 永久侧门 L（`switch` 臂表位邻形，23 形 = 控制臂 4 + 邻形 19）

| 资产 | md5 | 备注 |
|---|---|---|
| `fuzzy_scripts_720/tmp/c010l_switch_armslot_gate_tmp.sh` | `babe087708ec2e518f06c1cea2100ee4` | 门 L v1，`gate_rev=v1`，头行内嵌 §3.8.1 实测规则 |
| `fuzzy_scripts_720/tmp/c010l_presnap/prefix.tsv` | `8a0116db0108bb97147661ede573c854` | **注册读数 = 落地前**（`same=9 over_accept=6 both_reject=7 aot_only_red=1`，`ELAPSED=50s`）⇒ 落地前快照，永久保留 |
| `fuzzy_scripts_720/tmp/c010l_switch_armslot_tmp.tsv` | `19cac57546634f4d748f2d96893b1857` | **验收读数 = 落地后**（`same=10 over_accept=0 both_reject=13 aot_only_red=0`，`ELAPSED=33s`） |
| `fuzzy_scripts_720/tmp/c010_r5_presnap/`（11 枚 TSV） | — | 全链复跑前的各门快照（K/L/J/D8/E/F/G/H/H2/I/影子） |
| `fuzzy_scripts_720/tmp/c010_r5_acceptance_chain_tmp.sh` / `…_rowdiff_tmp.sh` | — | 十门 → 主回归 → 影子的串行验收链 + 逐行 `diff_rows` 比对器（排除 `#` 表头与 `ELAPSED`/`*_DONE` 行） |

**判据**：承 §3.5.1 五桶契约逐字同口径；`compile_fail` 以**产物可执行性**判（记忆规则 21）；`--compile` 在仓库根执行。

#### 3.8.4 读数对照（注册＝落地前 → 验收＝落地后）

| 门 | 落地前 | 落地后 | 判读 |
|---|---|---|---|
| **L**（23 形） | `same=9 over_accept=6 diff_php_ok=0 both_reject=7 aot_only_red=1 run_red=0` @`50s`（2.2 s/形） | `same=10 over_accept=0 diff_php_ok=0 both_reject=13 aot_only_red=0 run_red=0` @`33s`（**1.4 s/形**） | **过度接受 6→0**；**硬守卫 1→0**（§3.8.5）；目标全达成 |
| **K**（24 形，面 A 取证门） | `same=8 over_accept=4 diff_php_ok=1 both_reject=6 aot_only_red=5` @`42s` | `same=8 over_accept=0 diff_php_ok=1 both_reject=10 aot_only_red=5` @`31s` | §3.7 面 A 的 **4 枚 OVER_ACCEPT 全转 BOTH_REJECT**（逐行差 = 恰好这 4 行）；`aot_only_red=5` 恒 = 面 B（属 011）⇒ **本批不该动它，实测也没动它** |

**门 L 的 12 行逐行变化（vs `c010l_presnap/prefix.tsv`）= 6 枚判据翻转 + 1 枚红闭合 + 5 枚同桶消息精确化**：

| 形 | 前 → 后 | AOT 新日志（归一后） |
|---|---|---|
| `l_two_semi_arm_list` | OVER_ACCEPT → **BOTH_REJECT** | `syntax error, unexpected ";", expecting "}"` |
| `l_assign_before_case` | OVER_ACCEPT → **BOTH_REJECT** | `syntax error, unexpected variable "$a", expecting "}"` |
| `l_var_before_case` | OVER_ACCEPT → **BOTH_REJECT** | 同上 |
| `l_alt_if_before_case` | OVER_ACCEPT → **BOTH_REJECT** | `syntax error, unexpected token "if", expecting "}"`（该形是**花括号** switch 内嵌 `if():…endif;` ⇒ 报 `}` 正确） |
| `l_endif_stray` | OVER_ACCEPT → **BOTH_REJECT** | `syntax error, unexpected token "endif", expecting "}"` |
| `l_bare_colon_arm_list` | OVER_ACCEPT → **BOTH_REJECT** | `syntax error, unexpected ":", expecting "}"` |
| **`l_alt_semi_arm`** | **AOT_ONLY_RED_COMPILE → SAME_BOTH_ERROR_LIKE**（`php=A` / `aot=A`） | 见 §3.8.5 |
| `l_bare_block_arm_list`、`l_bare_block_nested`、`l_semi_then_block` | 同桶（BOTH_REJECT）仅消息变 | `Unexpected token in expression` → `syntax error, unexpected "{", expecting "}"` |
| `l_if_before_case`、`l_for_before_case` | 同桶仅消息变 | → `unexpected token "if"/"for", expecting "}"` |

⇒ **控制臂零扰动实测**：`l_ctl_case_first`/`l_ctl_default_first`/`l_ctl_empty`/`l_ctl_between_arms` 与 `l_semi_arm_list`/`l_semi_only`/`l_case_before_default`/`l_nested_brace_inner`/`l_semi_between_arms` 九枚 **逐字节 IDENTICAL** ⇒ §3.8.1 的单枚分号豁免支没有把任何 PHP 合法形新拒。

#### 3.8.5 顺带闭合：**R-3 批的漏网硬守卫红** `l_alt_semi_arm`

落地前门 L 唯一一枚 `aot_only_red=1` 与本单面 A **无关**：

- 形：`switch (1): ; case 1: echo "A"; endswitch;`（PHP **rc=0** 输出 `A`）
- R-3 代次实测：`Parse error: syntax error, unexpected ";", expecting "endswitch"` ⇒ **无产物**
- 机制：R-3 批把替代语法的 `endswitch` 改为硬 `eat`（`:3620–3623`），而**臂表位那枚合法的空语句分号**从未被消费 ⇒ `eat(.k_endswitch)` 停在 `;` 上。
- ⇒ **门 J 的 29 形未探「替代语法 `switch` 的 case 列表首有分号」这一位**（门 J 覆盖 `end*` 闭合位，不覆盖该邻位）⇒ 该红在 R-3 验收链里是**覆盖意外**，不是回归判据漏读。
- 本批的豁免支（③）在任何语法下先消费单枚 `;` ⇒ 该形转 `SAME_BOTH_ERROR_LIKE`（`A` vs `A`）⇒ **R-5 同时是 R-3 批的补丁**。

#### 3.8.6 parseSwitch 锚点漂移登记（**引用本单/011 旧行号前必读**）

本批 ③ 在 `parseSwitch` 中部插入 17 行 ⇒ §3.7/§5 与 011 内的旧锚点整体后移。**实测新行号（当代次 `parser.zig 1eab26c0…`，`grep` 复验）**：

| 语义 | 旧引用 | **当代次实测** | 漂移 |
|---|---|---|---|
| `case` 臂的 `eat(.colon)`（面 B 根，011 R-B1） | `:3571` | **`:3580`** | +9 |
| `default` 臂的 `eat(.colon)`（面 B 根，011 R-B1） | `:3583` | **`:3592`** | +9 |
| 意外 token 的 `else` 支（面 A 根，**本批已改**） | `:3592-3597` | **`:3608–3614`**（严格 `break` 单枚在 **`:3612`**） | +16 |
| **本批新增**：单枚空语句分号豁免支 | —— | **`:3601–3607`**（判定头 `:3601`、置位 `:3606`） | 新增 |
| switch 关闭 `eat(.r_brace)` | `:3611` | **`:3628`** | +17 |
| `.switch_stmt` 节点构造（面 C 根，011 R-C1） | `:3616` | **`:3633`** | +17 |
| `fn parseSwitch` | —— | **`:3555`** | 函数名实测为 `parseSwitch`（§3.7 行文中的 `parseSwitchStmt` 为口误，语义不变） |

**`parseSwitch` 之后的锚点：一致 +17（实测确认）**。本批 17 枚插入的分布 = 旗标字段声明 **6**（`:33–38`）＋ `initWithModeInsensitive` 置位 **2**（`:80–82`）＋ `parseSwitch` 体内 **9**（`:3571-3572`、`:3601-3607`）⇒ **`parser.zig` 中任何行号 > `:3634` 的锚点相对 R-3 代次恰好后移 17 行**。唯一实测确认点：`isAlternativeCloserTag` 在 §3.6 登记为 R-3 代次 `:3976`，当代次 `grep` 实测 **`:3993`** ⇒ `+17` ✓。

| 语义（历史引用） | 当代次实测（`1eab26c0…`） | 说明 |
|---|---|---|
| D-4 死桩 `isKeywordUsableAsIdentifier`（旧引 `:3756-3759`） | **`:3853-3856`** | 旧行号属 **R-2 代次**（比 R-3 更早）⇒ 本表非「+17」而是逐枚重测 |
| `isKeywordIdentifierTag`（旧引 `:3761`，§3.4.2 名位矩阵） | **`:3858`** | 同上 |
| `eatKeywordAsIdentifier`（旧引 `:3843`） | **`:3962`** | 同上 |
| `isAlternativeCloserTag`（R-3 代次 `:3976`） | **`:3993`** | ★ +17 的实测确认点 |

⇒ **引用本单/011 里任何 `parser.zig` 行号前先按本节换算**；行号本身随每批插入漂移，语义锚点（函数名 + 判定条件）才是稳定引用位。

**门脚本头注释同样停在落地前代次（实测，本批不编辑已登记门脚本）**：门 L 的脚本头（`c010l_switch_armslot_gate_tmp.sh`，md5 `babe087708ec2e518f06c1cea2100ee4`／139 行，**落地前建档 ⇒ 头注释为 R-3 代次**）引 `:3592-3597`（意外 token 支）、`:3596`（整枚跳过）、`:3611`（硬 `eat(.r_brace)`）三枚旧锚点 ⇒ **当代次实测 = 豁免支 `:3601–3607`、严格支 `:3608–3614`（`break` 在 `:3612`）、硬 `eat(.r_brace)` `:3628`**；门 K 的脚本头（`c010_brace_switch_gate_tmp.sh`，md5 `6408a6b6…`）同属落地前代次，口径一致。
处置决策：**只在工单登记漂移，不改门脚本头注释** ⇒ 已登记门脚本的 md5 与读数表保持逐字节可复现（改形须先回显再重登，见 §7-9）。

> 追加一条坑（本批实测）：**「门在哪一批建，门头的源码锚点就属于哪一批的代次」**。守卫门按流程必须在落地**前**建立，所以它的头注释天然引用落地前的行号；落地后引用门头的锚点会指向已被挪动的语义位（本例 `:3596` Today 落在别处）。⇒ 复现门判据时按本节换算表取行号，**不要**按门头取。

#### 3.8.7 代次锚点（本批 = 新代次）

| 资产 | md5 |
|---|---|
| `zig-out/bin/php-interpreter` | `6939cd2e891f20aef590de2585b15681`（R-3 批为 `81f8a55a…`） |
| `src/compiler/parser.zig` | `1eab26c068b13b9f904d2f432464d852`（R-3 批为 `5ad452fe…`） |
| `src/compiler/lexer.zig` / `keyword_lookup.zig` | `e3dd4191a1c3dfdf816b5873b4c60e5f` / `ef70993a7caac6deb9b2e5a23bf7d143`（**与 R-3 批全等 ⇒ 本批零触碰前端词法**） |
| `git HEAD` | `f9432e2`（R-2 六枚修复源码已入库于 `0652130`；**本批 + 文档 + 门资产均未提交**） |

⇒ 按 §9 的代次口径，本批**改了 `parser.zig`** ⇒ 等价取证（§9.2 的 md5 对照）不适用，**必须走整链**（十门 + 主回归 + 影子）。

#### 3.8.8 流程负面记录（登记为口径，非面孔）

本轮踩到**双层后台**事故：在 `run_in_background` 的命令里再套 `nohup bash -c '…' &` ⇒ harness 立即报「完成」，而真实的链仍在前台进程存活 ⇒ 我据该假完成信号又启动了一条链 ⇒ **两条链并发写同一批 TSV**，门 K 被截断到 1 行数据、门 J 出现 51 行／两枚 `_DONE`。处置：`ps ax -o pid,ppid,command` 追父进程映射 ⇒ `kill -TERM` 三个 pid ⇒ 删孤儿锁 `.zigphp_aot_build_11167` ⇒ 以**单层** `run_in_background` 重跑。另 `setsid` 在 macOS **不存在** ⇒ 一次启动静默失败（launcher 无输出）。⇒ **口径固化：`ps` 见进程存活 ≠ 已完成；后台链只允许单层；每轮复跑前先快照 TSV（本轮即 `c010_r5_presnap/`）**。

#### 3.8.9 结论

1. **§7-15c 面 A 收口**：花括号 `switch` 的 4 枚过度接受全部转为与 PHP 同向拒绝，门 K／门 L 的 `over_accept` 两列同时归零。
2. **旧措辞「一行」被实测否证**，真实形态为「旗标 + 单枚前导分号豁免」三处改动；该规则（`case` 列表首恰好一枚 `;`）现固化在门 L 表头与源码注释两处。
3. **R-3 批的替代语法硬守卫红 `l_alt_semi_arm` 由本批顺带闭合** ⇒ 门 J 的覆盖面缺陷登记为新口径：闭合位门**不覆盖臂表位邻形**。
4. **消息精确化为副产品**：5 枚同桶行的泛化文案（`Unexpected token in expression`）改为带 token 与期望集的精确文案 ⇒ §7 的「泛化消息（P2）」面收窄。
5. **面 B／C 未被触碰**（`aot_only_red=5` 前后恒等）⇒ 仍待 011 的 D-1…D-4。

#### 3.8.10 R-5 批全链实测读数（十腿门段 + 逐行等值比对器）

**链脚本** `fuzzy_scripts_720/tmp/c010_r5_acceptance_chain_tmp.sh`（md5 `df6eed2b557e5e5e935626629a07ca2e`）＝**十腿串行**（`K → L → J → D8 → E → F → G → H → H2 → I`，全部带 `timeout`）→ 主回归 → 影子；腿序按「先读本批直接判据（3 分钟内可见）、再吃长时间影子」排。

**十腿读数（R-5 代次 `6939cd2e…`／`parser 1eab26c0…`，`repo_build_residue` 全 = 0、`SMOKE_ONLY` 全 = 0）**

| 腿 | 读数 | `ELAPSED` |
|---|---|---|
| K（面 A 主验收） | `shapes=24 same=8 over_accept=0 diff_php_ok=1 both_reject=10 aot_only_red=5 run_red=0` | 31s（1.3 s/形） |
| L（过度拒绝守卫） | `shapes=23 same=10 over_accept=0 diff_php_ok=0 both_reject=13 aot_only_red=0 run_red=0` | 33s（1.4 s/形） |
| J（R-3 同支路 alt 语法） | `shapes=29 same=19 diff=0 over_accept=0 both_reject=10 aot_only_red=0 run_red=0 both_err_diff=0` | 66s |
| D8（§8 独立缺陷面） | `shapes=14 defect_red=1 guard_same=13 compile_fail=0 bad_probe=0` | 47s |
| E | `shapes=19 same=19 diff=0 silent_empty=0 aot_fatal=0 compile_fail=0` | 65s |
| F | `shapes=8 same=8 diff=0 zero_instr=0 compile_fail=0` | 26s |
| G | `shapes=7 same=7 diff=0 red_confirmed=0 guard_same=4 guard_red=0 compile_fail=0` | 24s |
| H | `shapes=79 arms=200 face=0 noface=78 confounded=1 bad_probe=0 ctrl_compile_fail=0 probe_compile_fail=0 inverse_shapes=21 inverse_face=0 inverse_noface=21` | 700s |
| H2 | `shapes=15 over_accept=12 strict_same=1 aot_compile_fail=2 both_reject=2 aot_only_red=0 php_ok_aot_diff=0` | 45s |
| I（跨模式分叉证明） | `shapes=19 tree_same=7 tree_diff=12 bc_same=7 bc_diff=12 aot_same=19 aot_diff=0 both_red=0 vm_only_red=12 aot_only_red=0` | 66s |

⇒ 逐腿 `ELAPSED` 之和 = **1103 s**；门段墙钟 `12:21:51 → 12:40:14` = **18m23s = 1103 s** ⇒ **两口径互证**（串行无并发污染，与记忆口径「带 `repo_build_residue` 的门禁不得与影子/主回归并发」一致）。

**逐行等值比对器** `fuzzy_scripts_720/tmp/c010_r5_rowdiff_tmp.sh`（对照 `c010_r5_presnap/`＝**R-3 代次落地前快照**，剔除表头与 `ELAPSED`/`_DONE` 行只比逐形数据行）：

| 门表 | `diff_rows` | 判读 |
|---|---|---|
| 门 K | **8**（= 4 行 × 旧/新） | ★ **恰为面 A 的四形**：`k_stmt_before_case`／`k_stmt_before_case_two`／`k_nested_stmt_head`／`k_stray_endswitch` 全部 `OVER_ACCEPT → BOTH_REJECT`；余 20 行逐字节不变 ⇒ **面 B 的 5 行仍 `AOT_ONLY_RED_COMPILE`（原文仍 `unexpected ";", expecting ":"`）、面 C 的 `k_default_first` 仍 `DIFF_PHP_OK_AOT_DIFF`** = 零触碰的实测证据 |
| 门 L | **24**（= 12 行 × 旧/新） | 拆 = **7 行改判**（`l_two_semi_arm_list`／`l_assign_before_case`／`l_var_before_case`／`l_alt_if_before_case`／`l_endif_stray`／`l_bare_colon_arm_list` 六枚 `OVER_ACCEPT → BOTH_REJECT` ＋ `l_alt_semi_arm` `AOT_ONLY_RED_COMPILE → SAME_BOTH_ERROR_LIKE`【§3.8.5 的 R-3 漏网闭合】）＋ **5 行仅文案变精确、判据不变**（`l_bare_block_arm_list`／`l_bare_block_nested`／`l_if_before_case`／`l_for_before_case`／`l_semi_then_block`，均 `php_rc=255` 的 `BOTH_REJECT`，AOT 文案由泛化 `Unexpected token in expression` 改为 `unexpected token "X", expecting "}"`）⇒ **形名集与新旧逐行完全对齐**（`cut -d'|' -f1` 逐字节相同 ⇒ 不存在行增删）。**权威指针：逐形清单与 AOT 新日志文案以 §3.8.4 的表为准，本行只登记比对器的行计数口径** |
| 门 J / D8 / E / F / G / H / H2 / I | **0** | 八腿逐形数据行**逐字节等值** ⇒ 本批对既有面零扰动；门 I 的 `tree_diff=12`/`bc_diff=12` 与冻结注册值逐项相同 ⇒ **旗标分叉（AOT-only）达成** |
| 影子表 | **0**（腿后复测，真等值） | ★ 中途读数**作废**：第一次 rowdiff 跑在影子腿开跑**之前**，读到的是 R-3 代次旧表 ⇒ 当时的 `diff_rows=0` 只是「旧表 vs 旧表」，已在 §3.8.11 以腿后复测替换。影子腿完成后（13:18:15）复跑比对器 ⇒ `old_rows=136 new_rows=136 diff_rows=0`，即对照侧 = `c010_r5_presnap/c010_shadow_main_md5_tmp.tsv`（R-3 代次 68 语料 × 新旧两列 md5）与新表**逐行逐字节全等** ⇒ **R-5 在语料面上实测发射中性**（跨 R-2 + R-3 + R-5 三批累计零漂移）。⇒ 口径固化：**长腿（主回归／影子）的等值必须在腿完成后复测比对器**，中途读数一律标注「禁引用」 |

**控制臂与豁免面核验（形名实测更正）**：门 L 的**四枚控制臂**为 `l_ctl_case_first`／`l_ctl_default_first`／`l_ctl_empty`／`l_ctl_between_arms`（全部 `php_rc=0`、当代判据 `SAME_BOTH_ERROR_LIKE`）——它们在 rowdiff 的 12 行变更清单里**一形未列** ⇒ 落地前后**逐字节未变**；另有**三枚豁免面对照形** `l_semi_arm_list`／`l_semi_only`／`l_alt_semi_arm`（`php_rc=0` 的「case 列表首单枚空语句分号」合法形）当代同样全部 `SAME_BOTH_ERROR_LIKE`，其中前两枚前后未变、第三枚 `l_alt_semi_arm` 由 `AOT_ONLY_RED_COMPILE` 转 `SAME`（§3.8.5）⇒ **`same` 列 9→10 的唯一来源即该形**。⇒ 两条结论同时成立：**豁免支没有误拒任何 PHP 合法形（含单枚分号三形与控制臂四形），也没有放过任何 PHP 非法形（六枚 `OVER_ACCEPT` 全部转 `BOTH_REJECT`）**。

#### 3.8.11 R-5 批长腿实测（主回归 + 影子）与全链墙钟 ⇒ §5 R-5 行的占位口径就此收口

**腿 2 = 官方主回归**（`fuzzy_scripts_720/run_regression.sh`，`timeout 1800`，12:40:14 → 12:53:08 = **12m54s**，`regression_rc=0`）：

| Total | Pass | Fail(Compile) | Fail(Runtime) | Fail(Diff) | Skip |
|---|---|---|---|---|---|
| 68 | **67** | 0 | 0 | 0 | **1**（`f004_oop_deep_inheritance_magic.php`，`PHP_error_exit=255`，基线保持） |

**腿 3 = 影子门**（`c010_shadow_main_md5_tmp.sh`，脚本 md5 `cb8183142569c0afbed4385478558c98`／53 行，`timeout 3600`，12:53:08 → 13:18:15 = **25m07s**）：`C010_SHADOW_DONE total=68 same=68 diff=0 miss=0 ELAPSED=1507s` ⇒ 相对**修复前冻结二进制 `1f15e4ce…`**（`/tmp/c010_prefix_backup/`）零漂移；与 §3.8.10 影子行的 `diff_rows=0`（对照 R-3 代次表）互证 ⇒ **R-5 的生成码与 R-3 代次逐字节相同**，即本批在 68 语料面上**实测发射中性**。

**全链墙钟（`c010_r5_acceptance_chain_tmp.log` 的六枚时间戳）**：

| 阶段 | 区间 | 墙钟 |
|---|---|---|
| [1/3] 十腿门段 | 12:21:51 → 12:40:14 | **18m23s**（= Σ `ELAPSED` 1103 s，两口径互证） |
| [2/3] 主回归 | 12:40:14 → 12:53:08 | **12m54s** |
| [3/3] 影子 | 12:53:08 → 13:18:15 | **25m07s** |
| **合计** | 12:21:51 → **13:18:15 `== ALL DONE`** | **56m24s** |

⇒ **R-5 批验收判据全部实测达成**（面 A 主判据 K/L + 八腿逐行等值 + 分叉判据门 I + 主回归 67/1 + 影子 68/68）；§5 路线 R-5 行里「本轮实测值随链日志登记」的占位口径由本节闭合，**引用链耗时一律取 56m24s**（R-3 批为 56m33s，两批同构、耗时同量级 ⇒ 十门口径的固定预算 ≈ **1 小时**，排期按此计）。

---

### 3.9 任务 #122e 落地轮：**R-125 goto 降级批**（§8 #3 关闭，门 D8 `defect_red=0`）——不触碰发射器，把规范后向 goto 在 IR 语句层降级为 do-while（2026-10-11）

**子轮定论前置（#122d）**：发射器（native_linker 函数体渲染）是基于索引区间的结构化渲染（`buildControlFlowBoundaries` ⇒ cond_br 的 then/else/merge 下标区间），**无条件 br 到非相邻块无 Zig 表示** ⇒ 标签块内容被静默丢弃——IR 侧行试验（去除 goto_after）已被实测否证回滚。

**R-125 形态（本次落地）**：绕开发射器——在 `generateMainFunction` 顶层语句走查加 **label→closer 配对**，把规范后向 goto 模式降级为 do-while IR（镜像 `generateDoWhileStmt` 的块图与 `do_while_*` 命名 ⇒ 发射器既有 do-while 机制原生出码）：
- `L: S…; if (C) { goto L; }` ≡ `do { S…; } while (C);`（**严格等价**：S 恒先执行一次，closer 的 C 决定重跑）
- `L: S…; goto L;` ≡ `do { S…; } while (true);`（rest 不可达 = PHP 语义）
- `gotoLoopCloserCondition` 判据 = 无 else 且 then 块仅含一条 goto L；`goto_labels.put(L → body_block)` 使体内嵌套 goto 解析为重跑边；`loop_stack.push` 使体内 break/continue 正确绑定
- 配对失败（多标签/双 goto/带 else 等非规范形态）⇒ `flushGotoLoopBuffer` 按原序生成（现状行为）；**R-126 起下沉为 `generateStatementListGotoAware` 共用助手**（`generateMainFunction` 与 `generateBlock` 共用 ⇒ 函数体/花括号块内的规范后向 goto 同样降级，f1/f2/f3 探针全绿）
- 附带收益：前向 `goto L; L: …` 的**尾随语句丢失**（历史 `12` vs PHP `123`）经 flush 路径一并修复（g1 探针 `123` ✅）

**验收实测（链 V，2026-10-11，合并态 = 本批 + 并行 R-3/R-5）**：
| 门 | 读数 |
|---|---|
| D8 | `defect_red=0 guard_same=13→14 compile_fail=0 bad_probe=0 residue=0 ELAPSED=50s`（d3a 转绿，**§8 七枚全数关闭**） |
| H | `face=0 noface=79 **confounded=0** inverse_face=0 inverse_noface=21 probe_compile_fail=0 ctrl_compile_fail=0`（k_goto 的 CONFOUNDED 清零，79+21 全绿） |
| H2/I | over_accept=12 both_reject=2（R-3 代注册值，零扰动）；tree/bc 四项逐项不变、aot_same=19 |
| 影子 | `total=68 same=68 diff=0`（语料 goto 0 处 ⇒ 零漂移实证） |
| 主回归 | Pass 67 / Skip 1（2026-10-11 00:32:47 报表） |
| 探针 | g1 `123` ✅ g2 `9` ✅ g3 `n3` ✅ g5 `aaa` ✅；g4（双 goto 非规范形态）维持现状 = 登记边界 |

**代次锚点**：R-125 代二进制 `5c436e9e48e816e666c8996f29d18138`（顶层配对）；**R-126 代二进制 `85b51931d0f5b79f2d681e1481a1ff3e`（配对下沉 generateBlock，链 VI = 门 D8 `defect_red=0 guard_same=14` + 门 H `face=0 noface=79 confounded=0 inverse_face=0` + 影子 68/68 + 主回归 Pass 67/Skip 1，2026-10-11 01:32:11 报表）**；**R-127 收尾代二进制 `7fbdbcf620de98b2c7bf69517b63c7a5`（closer 放宽 + 命名参数 CI + 运行期查名 CI 七处，链 VII 同口径全绿，g4/n1/n2/n4 探针全绿，2026-10-11 02:33:44 报表）**；`ir_generator.zig` `（当前树）`（+137 配对走查 + 下沉重构）；`parser.zig` `1eab26c0…`/4305 行逐字未动（R-5 锚点保持）。已知边界（R-127 后仅余）：**closer 的 else 位 goto**（`if (C) {X} else {goto L}` 形）与**类名族 CI**（`class_registry` 精确查，独立面孔未立单）；~~双 goto 连发~~（R-127 死代码判据解除）、~~命名参数 CI~~（R-127 三处扫描折形）、~~运行期查名族~~（R-127 `lookupUserFunctionCI` 七处：is_callable/动态调用×2/Closure 创建/go 协程/存在性判定×2）均已解除；函数体/块内边界已由 R-126 解除。

## 4. 语料面与风险

| 维度 | 结论 |
|---|---|
| 68 语料面（**穷举实测**） | `grep -onE '\b(Echo\|ECHO\|Print\|PRINT\|If\|IF\|Else\|ELSE\|Elseif\|Return\|RETURN\|Function\|FUNCTION\|Class\|CLASS\|New\|NEW\|ForEach\|FOREACH\|True\|False\|Null)\b' fuzzy_scripts_720/pass/*.php` ⇒ 命中 10 处（f016:196 `True`、f038:144 `New`、f072:180 `Function`、f113:192 `New`、f151:82 `Return`、f152:96/120 `Function`、f179:170 `If`/181 `Else`/295 `Function`/268 `Print`）⇒ **逐处回文核对：全部位于字符串字面量内**（如 `echo "New total: "`、`$this->output .= "If\n"`）⇒ **关键字位的混合大小写命中 = 0 处** |
| 判据 3/4 应用 | 「扫描器 0 命中 ≠ 语料 0 命中」在本单成立：扫描器有 10 处命中但**语料内真实触发面为 0** ⇒ 冻结基线对本面**零保护力**；同时该面**机制可达**（任何混合大小写关键字书写即命中），语料 0 只说明绿语料恰好全用小写 |
| **替代语法家族语料面**（2026-10-08，`token_get_all` 分词器实测，见 §3.6） | 与关键字大小写**无关**但共用同一 `lexer/parser` 前端 ⇒ 一并登记：冻结基线 `pass/` 68 文件 + `fail_runtime/` 77 + `fail_compile/` 12 的**替代语法开口头与关闭标记均为 0**（32 处粗筛命中全在字符串/注释内）⇒ 正例面（已支持）与负例面（5 形过度接受）**都不受官方回归保护**；同判据 4「机制完全可达」 |
| **`parseSwitchStmt` 三面孔语料面**（2026-10-09 任务 #126，两枚独立分词器扫描器互证，见 §3.7） | 面 A（首 `case` 前裸语句被跳）／面 B（`case`/`default` 分号终结符被假拒）／面 C（`default` 非末臂 ⇒ 臂序丢失 + 假执行）在 **249 个语料文件、7 枚 `switch`（全为花括号头、替代头 0）** 中的实测暴露面 **全为 0**：`stmt_before_first_case=0`、`semi_arm=0`、`nonlast_default=0`（对照组 `colon_arm=37` 证明扫描器对该构造有判别力）。基线 4 枚花括号 switch 站点已逐处回文核对（`pass/f048:118` default 末臂、`pass/f134:94/160`、`pass/f163:133` 三枚无 default，另 `fail_runtime/f082:98`）⇒ **判据 3/4**：三面孔均「语料内 0 且机制完全可达」⇒ 冻结基线零保护力；反过来说，parser 侧对该族的硬化／放宽对**合法代码**结构上发射中性（面 A 的「发射中性」已由推断升为实测，影子仍须跑）|
| R-2b 面语料穷举（任务 #119 实测） | `grep -onE 'constant\(' fuzzy_scripts_720/pass/*.php` ⇒ **0 命中**；`grep -onE '\bdefined\('` ⇒ **0 命中** ⇒ 冻结基线对常量表拼写面**零暴露**；同判据 3/4：语料 0 ≠ 机制 0，任何用 `constant("true")` 风格动态查名的现网脚本即命中 |
| 静默性 | **本单最危险处**：三形空输出 + 一形错臂双输出 + 一形错值全为 rc=0、无 warning、无 fatal ⇒ 若用户脚本用 `Echo`/`Print`/`IF`/`RETURN` 风格书写，官方回归「输出比对」会抓到（语料内无此形 ⇒ 现网脚本才会踩）；反之「整段静默不输出」在只看 exit 码的门里会被判绿 ⇒ 侧门 E 的 `silent_empty` 计数器专门盯这一类 |
| 修复的破坏面 | 前端 lexer 改动 ⇒ **触发冻结基线漂移风险**（`main.zig` 生成码取决于 token 序列）；但语料关键字位混合大小写 0 处 ⇒ 只要改动只让「原先查不中的拼写」命中，理论上发射中性，**该中性未影子实测**。风险点：PHP 的标识符大小写规则不统一（类/函数名不敏感、变量敏感），若在 lexer 层无条件归一化大小写会**误伤变量名/类名原文**，必须先定「只在关键字位查表归一、token 文本仍交原文」的形态 |
| **门 H/H2 派生独立缺陷的语料面**（任务 #120 穷举实测，`fuzzy_scripts_720/pass/*.php` 68 文件） | 逐族回文核对 ⇒ **两类**：① **有面且已绿** = `callable` 类型位 **59 处**（f047×16、f152×14、f042×6、f090×5、f151×3、f171×2、f163×2、其余各 1）⇒ 小写 `callable` 在 AOT **可用**（修模板后侧门 H 判为 `FACE`：只有混合拼写红）；② **语料面 0** = `and`/`or`/`xor` **真运算符位** 0 处（35 处命中全在字符串字面量/注释内；另 14 处非字符串命中**全部是用户自定义方法名** `->and()`/`->or()`/`::xor()` ⇒ 恰好落在「标识符名位容忍」支上 ⇒ **语料绿直接依赖该容忍支**）、`var` 属性声明 0、`goto` 0、`iterable` 0、`__NAMESPACE__` 0 ⇒ 判据 3/4 同 §4 上表：这些族的红面对冻结基线**零暴露**，但机制可达（现网脚本用即命中） |
| **标识符名位容忍面**（任务 #120 只读实文 + 实测计数） | `parser.zig:3761 isKeywordIdentifierTag` **实测只列 74 枚 `.k_*` tag**（**本行旧措辞「全部 87 枚」经 `:3761`–`:3840` 逐枚计数为错，已更正**）。表内 80 枚小写 `k_*` 中**被排除的 6 枚** = `.k_endfor` `.k_endforeach` `.k_endif` `.k_endswitch` `.k_endwhile` `.k_struct`；魔术常量 7 枚为另一套 tag，不在此清单。容忍支经 `:3843 eatKeywordAsIdentifier` 在 **8 处**名位调用（`:762`、`:946`、`:1263`、`:2181`、`:2465`、`:2524`、`:2563`、`:2869`）⇒ 语料实测命中：`->(get\|set\|lock\|from)` **45 处 / 8 文件**（f037×15、f016×8、f056×7、f173×7、f178×4、f010×2、f057×1、f040×1）、`public function (get\|set\|lock)(…)` 声明 **24 行 / 7 文件** ⇒ **全部落在名位 ⇒ 语料绿与此容忍支直接相关**。⇒ 结论（**已由门 H 反例组 21 形实测坐实，不再是推断**）：被抢注成 token 在**有容忍支的名位**不致害（`invm_*` 六枚绿），致害面在**无容忍支的名位** = 顶层函数名 `:1405` 与类名 `:1319-1321`（`invf_*`/`invd_*` 各 7/7 红）+ **清单漏项名位**（`invm_struct` 红，因 `.k_struct` 不在 74 枚内）⇒ 详见 §3.4.2 |

---

## 5. 修复路线（优先级 / 影响面 / 落地成本 —— 成本列为「实测」或「未实测」，禁列估算）

> **落地状态（2026-10-07）**：**R-2 / R-2b / R-4 已落地并验收**（形态与实测读数见 §3.4.6；R-2 与名位补洞同批 = D-1 甲裁决，分叉旗标门控 = D-2 裁决）；**R-3（金丝雀）仍未启动**。落地实测成本：验收链 II = 影子 ~2400s + 六门 822s + 主回归 ~834s；源码改动 8 文件 +268/−78 行（git diff HEAD 实测）。
>
> **★ 编号消歧（2026-10-09，必读）**：2026-10-09 落地的批次在 `parser.zig` 源码注释与 §3.6 里记作 **「R-3 批」**（＝本单第 3 个修复批次，内容是 §3.6 门 J 的 P1「替代语法严格闭合」旗标门控），**与本节路线 `R-3`（发射期静默金丝雀）不是同一件事** ⇒ 下表 **R-3 路线的状态仍是「未实测／未启动」**，任何会话不得因「R-3 批已落地」而把金丝雀路线判为已收口。后续若重命名需先改注释再改文档，二者必须同时改。

| 路线 | 内容 | 优先级 | 影响面 | 落地成本 |
|---|---|---|---|---|
| **R-1** | ~~归因轮（前置）~~ **已闭环（任务 #119，永久侧门 F）**：五类下游断点逐类到行，见 §3.1 | P0 前置 | 只读，零源码改动 | **实测 `ELAPSED=30s` / 8 形 = 3.75 s/形**（含生成码结构实读一枚额外编译；另侧门 E 19 形 `60s`） |
| **R-2** | 关键字查找改大小写不敏感：`keyword_lookup.zig` 增加忽略大小写的查表路径（`lookup` 侧一次性归一，或 `eqlIgnoreCase` 线性/两级分派），`lexIdentifier` 仍交**原始 token 文本**（勿把归一化后的文本喂给 identifier 语义）。**形态先例（任务 #120 只读实文）**：`parser.zig:3857` 名位标识符名取自 `self.lexer.buffer[name_tok.loc.start..name_tok.loc.end]`（**原文切片**，不经任何大小写归一）⇒ 「查表归一 + 文本交原文」的分工在前端里**已存在**，R-2 只需照此形把 `keyword_lookup` 的查表侧改敏感、名位取文本侧保持原样，非新发明 | P0（本单收口） | **验收面已实测穷举（任务 #120，门 H）= 59 形**：34 FACE（含 2 枚仅警告噪声 ⇒ 语义红 32）+ 25 探针编译失败 ⇒ 语义红面合计 **57 形**；另有 15 枚「宽容绿」须按 §3.4.5 判据 2 **比对生成码**才算收口。编译前端全量 token 流 ⇒ **可能触发冻结基线漂移**；须先影子实测 68 语料 `main.zig` md5。**新增实测约束（本代次更正，旧措辞「名位对 R-2 中性」已作废）**：`isKeywordIdentifierTag`（`:3761`）**实测只列 74 枚** `.k_*` tag，且顶层函数名 `:1405`／类名 `:1319-1321` **根本没有**容忍支 ⇒ 名位**并非**对 R-2 中性。R-2 落地后 `Echo` 类混合拼写将改走 `k_echo` 支；**同时** `function Get()`／`class With()` 一类**今日因查表落空而侥幸绿**的混合大小写外族词会**首次**命中 `.k_get`/`.k_with` ⇒ 在这两处硬名位**新增编译失败面**（今日实测该面 0 红，见 §3.4.2 补充探针 1）⇒ **R-2 必须与「两处名位补 `eatKeywordAsIdentifier` 兜底 + 继续 intern 原文切片」同批落地**，并一并核对清单漏掉的 6 枚 tag（`.k_struct` 已实测在方法名位致红）。另需核对**魔术常量组**（表键 `__DIR__` 等为大写、表内 7/87 枚为此规范，归一方向取反反而**丢**命中 ⇒ 门 H 的 `m_*` 六形为其判据） | **未实测**（落地后必须跑的门与**实测单价**：门 E `60s` + 门 F `30s` + 门 G `26s` + 门 H `595s` + 门 H2 `54s` + 门 I `57s` = **822s**，再加 68 语料主回归 `run_regression.sh` 与影子 md5 对照 ⇒ 验收门合计约 **14 分钟**（不含主回归）；H2/I 为**守卫门**，预期读数不变（§3.5、§6）） |
| **R-2b** | **常量表拼写面（与 lexer 缺陷无关的第二张独立面孔，任务 #119 实测新立 ⇒ 永久侧门 G）**：运行期常量表按**大写单拼写**建键（`runtime_lib_template.zig:7614/:7615/:7637`）⇒ **动态查名入口**实测红：`constant("true")` PHP `a=true` vs AOT `Fatal: Undefined constant "true"`；`constant("false")`/`constant("Null")` 同红。覆盖面实测收窄到**仅 `true`/`false`/`null` 三枚**：`constant("php_int_max")` 在 PHP 8.5.8 **亦** Fatal 且 AOT 侧逐字节等值 ⇒ 非关键字常量本就该敏感；`define("GgC1",7)` 后 `constant("GgC1")` 两侧同 `7`、`constant("ggc2")` 两侧同 Fatal ⇒ 用户常量侧 AOT 与 PHP **已等值**，扩面即为回归。⇒ **R-2 只改 lexer 对该面零收敛**（探针源码内无任何大写关键字拼写） | P0（本单第二张面孔） | 生成码 `getGlobalVar` 的 `runtime.constants.get(name)` 查名路径（`main.zig:1066-1070`）**或**常量表建键侧；二者取其一即收口，需先定形态，且**限定只放开三枚关键字常量名** | **取证已固化为永久侧门 G**（7 形实测 `ELAPSED=26s` = **3.7 s/形**，逐形读数见 §3.3；其中一枚因 `cd` 到仓库根以外目录执行而报 `executable generation failed: FileNotFound` 且无产物 ⇒ **复测必须在仓库根**）；落地成本未实测 |
| **R-3** | 静默面兜底金丝雀：发射期断言「语句位置出现 `t_string` 且其原文忽略大小写等于关键字表条目 ⇒ 立即报错」，把「静默空输出」在任何修复前后都转成**编译期可见错误** | P1（防回归） | 只加断言支路，不改语义；对合法脚本零影响。**覆盖面实测收窄**：§3.1 D 类与 E 类**均非零指令**（`m_else_upper` 的 `instr=9 echo=2` 与控制臂**逐位相同**；`m_true_upper` 为 `instr=10`）⇒ 零指令金丝雀**只能抓 A 类**，D/E 类需另行判据 | **未实测**（可参考 CODEGEN-005/006 系列发射期金丝雀先例） |
| **R-4** | `lexIdentifier:390/:394` 的 `len <= 15` 硬编码上限改为按表内最长键计算（消除「更长关键字静默不查」的潜在面） | P2 | **本代次实测更正**：87 枚键最长为 `__NAMESPACE__`（13 字符）⇒ 距上限**仅剩 2 字符余量**（旧措辞「最长 9 字符 ⇒ 现在无面」已按 `grep -oE` 实测更正）。现在仍无面，但「未来静默失效」的距离比旧估计近得多；且 **R-2 若改为「忽略大小写两级表 / 折叠副本表」，表结构一旦重排就必须同步把上限改为按表计算**，否则新增条目可能悄悄越界 ⇒ 与 R-2 **同批**做，零额外成本 | **未实测**；若与 R-2 同批则零额外成本 |
| **R-5** ✅ **已落地（2026-10-09 任务 #127，面 A 收口）** | ~~`parser.zig:3595` 的 `if (is_alternative and self.strict_alt_closers) break;` 去掉 `is_alternative and`~~ **【该形态被 §3.8.1 实测否证：`case` 列表首恰好接受一枚空语句分号为 PHP 合法形，直改会把 `l_semi_arm_list`/`l_semi_only` 砸成硬守卫红】** ⇒ **实际落地三处**：① 新旗标 `Parser.strict_switch_case_list`（`:38`）② 仅由 `initWithModeInsensitive`（`:82`，即两枚 AOT 入口）置位 ⇒ 解释器/字节码构造点恒 `false`、行为逐字节等于历史 ③ `parseSwitch` 的**单枚前导分号豁免支**（`:3572` 标记 + `:3601–3607` 消费）与严格支 `if (self.strict_switch_case_list or (is_alternative and self.strict_alt_closers)) break;`（`:3612`），停原位后由 `:3620`/`:3628` 的硬 `eat` 报精确 unexpected | P1（§7-15c 收口位） | 覆盖面实测 = 门 K **4 枚** + 门 L **6 枚** `OVER_ACCEPT` 全部转 `BOTH_REJECT`；**顺带闭合 R-3 批的 1 枚硬守卫红** `l_alt_semi_arm`（替代语法臂表位分号，§3.8.5）；副产品 = 5 枚同桶行的消息由泛化 `Unexpected token in expression` 改为带 token/期望集的精确文案（收窄 §7 的 P2 消息面）；语料面实测 **0**（两枚扫描器互证 + 4 枚基线 switch 逐处回文核对，§3.7/§4）⇒ 合法代码永不进入该 `else` 支 ⇒ 结构上发射中性，**影子已实测**（见下方验收读数）；★ 门 L 的 **9 枚控制臂逐字节 IDENTICAL** ⇒ 豁免支未新拒任何 PHP 合法形 | **实测**：`git diff --numstat src/compiler/parser.zig` = 81/−6（本批净 **+17/−0**，三处）；门 L `50s`→`33s`／23 形（**2.2→1.4 s/形**）、门 K `42s`→`31s`／24 形；**全链验收（十门 → 主回归 → 影子）读数见 §3.8.4 与 §6「R-5 批落地后实测读数」**（链墙钟**实测 56m24s** = 十门 18m23s（Σ `ELAPSED` 1103s，与墙钟双向互证）+ 主回归 12m54s（774s）+ 影子 25m07s（1507s）；与 R-3 批实测 56m33s 同构 ⇒ **今后「十门 + 主回归 + 影子」的链预算一律取 ≈1 小时**，旧「4.3 分钟／形」类估算禁用） |
| ~~门 K 面孔 B／C 的修复路线~~ | **不属本单根** ⇒ **已另立 [AOT-CODEGEN-011](AOT-CODEGEN-011-switch-case-semicolon-terminator-and-default-arm-position.md)**（2026-10-09 立项，路线 **R-B1**／**R-C1**+**R-C2**，待裁决项 D-1…D-4 见该单）：面 B = `parser.zig:3571`/`:3583`（**★ R-5 落地后当代次实测漂移为 `:3580`/`:3592`，完整漂移表见 §3.8.6**）的 `eat(.colon)` 硬只认冒号，使 PHP 合法的 `case expr;`／`default;`（8.5 仅 Deprecated）被 AOT **假拒绝** 5 枚；面 C = `parser.zig:3616`（**当代次 `:3633`**）的 AST **无 default 位次**（`{expression, cases, default}`）× `ir_generator.zig:3211-3221`/`:3236-3237` 把 default 强制链为末臂 ⇒ 丢 fall-through **与** 假执行（六形实测，§3.7） | P1（面 B，假拒绝比宽容更致命）／P2（面 C，需先定 AST 形态） | 两面孔语料面均实测 **0**（`semi_arm=0`、`nonlast_default=0`）⇒ 零回归数据可依赖，且面 C 需动宪法 §一 超大文件 `ir_generator.zig`（改前必须 grep 既有模式） | 面 B 实测 = **两行**，验收链同 56m33s 可复用；面 C **未实测**（无既有验收链可套，AST 形态先定） |

**门控声明（2026-10-09 任务 #127 更新）**：R-1 归因轮与 R-5／门 K 面孔 B、C 的取证（任务 #119/#126）均属「只读取证」，已在 `继续推进` 授权范围内完成且**零 `src/` 改动**；**R-5 已于同一授权下落地并验收**（形态＝§5 R-5 行；老铁指令「继续推进已知问题修复」＝对已接受计划的推进授权，本批未偏离方向）⇒ 该批**只在 AOT 侧生效**（`strict_switch_case_list` 仅由两枚 AOT 入口置位，解释器/字节码构造点缺省 `false`、行为逐字节等于历史 ⇒ 宪法 §五 未越界，无需跨模式裁决）；**R-2 金丝雀路线（本节 R-3）与 R-4 仍待老铁点头**（宪法 §六：编译前端语义改动 + 可能改变发射形态）。**门 K 面孔 B／C（= AOT-CODEGEN-011）在本批零触碰**（实测证据：门 K `aot_only_red` 前后恒 5、门 L 形集不含该族），其 D-1…D-4 裁决未答 ⇒ 禁止顺带动。

---

## 6. 复测路径（体验流程）

```bash
cd /Users/wangjianjun/products/parser

# 永久侧门 E（19 形，实测 60s）
timeout 480 bash fuzzy_scripts_720/tmp/c010_keyword_case_gate_tmp.sh
# 当前代次预期：C010KW_DONE shapes=19 same=8 diff=8 silent_empty=3 aot_fatal=3 compile_fail=3，ELAPSED=60s（= 3.2 s/形）
# 修复后预期：same=19 diff=0 silent_empty=0 aot_fatal=0 compile_fail=0
#   分批口径（勿笼统引用）：R-2 单落地 ⇒ 八枚 DIFF 全转 SAME，三枚 COMPILE_FAIL 形同时转绿（同一根）；
#   若只落 R-3 ⇒ 三枚 silent_empty 变编译期报错（`compile_fail` 由 3 升至 6，same 不升）⇒ 属「止血可见化」而非修复，不可当验收通过
# 七枚 `*_ctl` 控制臂**必须始终 SAME**；`kw_bool_upper` 亦必须保持 SAME

# 永久侧门 F（R-1 归因门，8 形，实测 30s）
timeout 300 bash fuzzy_scripts_720/tmp/c010_mechanism_gate_tmp.sh
# 当前代次预期：C010MECH_DONE shapes=8 same=4 diff=4 zero_instr=1 compile_fail=0，ELAPSED=30s（= 3.75 s/形）
#   逐形发射面（instr/echo/gvar 三列即 A~E 类判据）：
#     m_echo_bare_ctl   SAME instr=2  echo=1                      ← 控制臂，instr 必须 >0
#     m_echo_bare_title DIFF instr=0  echo=0                      ← A 类零指令铁证（本门唯一 zero_instr）
#     m_echo_paren_title DIFF instr=3 echo=0 undef=…function Echo ← B 类（与上形只差一对括号）
#     m_true_lower_ctl  SAME instr=10 echo=3 gvar=none            ← 小写走 k_true 字面量路
#     m_true_upper      SAME instr=10 echo=3 gvar=getGlobalVar("TRUE")  ← E 类「对错的路」
#     m_true_title      DIFF instr=10 echo=3 gvar=getGlobalVar("True")  ← E 类第二张面孔（Warning+NULL）
#     m_else_ctl        SAME instr=9  echo=2                      ← 控制臂
#     m_else_upper      DIFF instr=9  echo=2                      ← D 类：计数与控制臂**逐位相同** ⇒ 落点缺陷
# 修复后预期（R-2 单落地）：same=8 diff=0 zero_instr=0，且 m_true_upper 的 gvar 列应变为 none（转字面量路）
#   若 instr 列在控制臂上变 0 ⇒ 是门坏了（KEEP_TEMP 抽取顺序），不是编译器变了

# 永久侧门 G（R-2b 常量表拼写面，7 形，实测 26s；必须在仓库根执行）
timeout 300 bash fuzzy_scripts_720/tmp/c010_constant_case_gate_tmp.sh
# 当前代次预期：C010G_DONE shapes=7 same=4 diff=3 red_confirmed=3 guard_same=4 guard_red=0 compile_fail=0，ELAPSED=26s（= 3.7 s/形）
# 修复后预期：R-2b 落地 ⇒ same=7 diff=0 red_confirmed=0；
#   **guard_red 必须恒为 0**：两枚守卫臂（`constant("php_int_max")`、`constant("ggc2")`）在 PHP 侧本就 Fatal，
#   一旦转红即证明修复把常量表查名改成了**全局**忽略大小写（越界），须回退到「仅三枚关键字常量名」形态

# 永久侧门 H（87 枚表项穷举双臂 + 21 形过度识别反例组，共 100 形，实测 595s；必须在仓库根执行）
timeout 900 bash fuzzy_scripts_720/tmp/c010_kw_full_table_gate_tmp.sh
# 当前代次注册读数：
#   C010H_DONE shapes=79 arms=200 face=59 noface=15 confounded=5 bad_probe=0
#              ctrl_compile_fail=1 probe_compile_fail=25 probe_timeout=0
#              inverse_shapes=21 inverse_face=15 inverse_noface=6 inverse_confounded=0
#              repo_build_residue=0 SMOKE_ONLY=0     ELAPSED=595s（= 6.0 s/形）
# 修复后预期（R-2 单落地，逐条对应 §3.4.5 判据，勿只看总数）：
#   ① face→0 且 probe_compile_fail→0（59 形全收敛）
#   ② noface=15 仍绿**且须比对生成码**（其绿当前来自宽容支 ⇒ 计数等值不足以收口）
#   ③ confounded=5 **不要求转绿**，只要求 ctrl/probe 两臂一致（这五枚与拼写无关，需另立单）
#   ④ inverse_face 必须**仍为 15**、inverse_noface 仍为 6 ⇒ 变大 = 把词表改成了保留字表（越界）；
#      变小 = 动了外族词集合（同样越界）
#   ⑤ m_* 六形必须由红转绿而非转更红 ⇒ 若 m_dir/m_file/… 的 AOT 值变空 ⇒ 归一化方向被写反（折小写）
#   ★ 额外新增面反查（门 H 不覆盖，须手跑 §3.4.2 补充探针 1）：`function Get()` 修复后必须**仍为 1**
# 门侧固化坑：`norm()` 只剥离行首 `PHP `、不折叠双空格 ⇒ 引用 FACE 必须同时给 34（含噪声）/32（语义）
# `ONLY=` 冒烟通道写入独立 `*_smoke_tmp.tsv`，总数行带 `SMOKE_ONLY=1` ⇒ **禁止当全量读数引用，用完必须删除**

# 永久侧门 H2（15 枚 NOFACE 成因判别 = 同位换瞎词，实测 44s）
timeout 300 bash fuzzy_scripts_720/tmp/c010_noface_tolerance_gate_tmp.sh
# 当前代次预期（R-3 落地 + 任务 #125 修门后，脚本 md5 582ca74d…）：
#   C010H2_DONE shapes=15 over_accept=12 strict_same=1 aot_compile_fail=2 both_reject=2 aot_only_red=0 php_ok_aot_diff=0，ELAPSED=44s（= 2.9 s/形）
# ★ 判读（修门后口径）：本门不比谁对，只比「AOT 是否接受 PHP 不接受的」⇒ over_accept 计数即「宽容位」清单；
#   但「AOT 拒」必须再看方向 ⇒ `aot_compile_fail` 现为**拒绝总数 = both_reject（收敛）+ aot_only_red（真回归，硬守卫须 0）**，
#   引用时禁止单独拿 `aot_compile_fail` 当红面（旧版四桶把它压成单计数，2026-10-09 R-3 批据此误判过一轮，见 §3.5.1）
# 历史读数（勿作当代次引用）：#120 代次 `over_accept=14 strict_same=1 aot_compile_fail=0` @54s（R-2 前，脚本 md5 8e11de20…）
#   ⇒ R-2 落地后曾判「瞎词臂不受影响」，R-3 把关闭标记位 2 枚收为同拒 ⇒ 14→12（见 §3.6「R-3 批落地实测」）
# 修复后预期：`Zkwhq` 仍**不是**关键字 ⇒ over_accept **应保持 12 不变**（本门不是修复验收门，是成因门）
#   ⇒ 若 over_accept 归零，说明改动把「任意标识符」也吞进了关键字支（越界），须回退
#   ⇒ 唯一零判别形 `n_never`（PHP 对未知返回类型在 throw 形不报错）永久保持 strict_same
#   ⇒ aot_only_red 任一枚转正 = 真回归（PHP 通过而 AOT 拒），须立即归因

# 永久侧门 I（跨模式 AOT/tree/bytecode，门 E 同批 19 形，实测 57s）
timeout 480 bash fuzzy_scripts_720/tmp/c010_crossmode_gate_tmp.sh
# 当前代次预期：C010I_DONE shapes=19 tree_same=7 tree_diff=12 bc_same=7 bc_diff=12 aot_same=8 aot_diff=8 aot_compile_fail=3 both_red=11 vm_only_red=1 aot_only_red=0，ELAPSED=57s
# 修复后预期（R-2 天然三模式同修 ⇒ 见 §2.2 结论 1）：tree_same=19 bc_same=19 aot_same=19，三种 _diff 与 aot_compile_fail 全 0
#   **七枚 `*_ctl` 控制臂在三模式下必须始终 SAME**；`norm()` 已含「从 `=== PHP Interpreter Performance Statistics ===` 起整段删除」，
#   若某日全部 VM 臂恒 DIFF ⇒ 是 VM 统计段标题变了（门坏），不是编译器回归

# 永久侧门 J（替代语法正/负例，v3 = 29 形；v2 = 23 形 77s、v3 实测 70s = 2.4 s/形；必须在仓库根执行）
timeout 300 bash fuzzy_scripts_720/tmp/c010_alt_syntax_gate_tmp.sh
# 注册读数（v3 全量，脚本 md5 592ef974…／表 md5 2a25520c…，R-3 落地代次 二进制 81f8a55a… / parser 5ad452fe…）：
#   C010J_DONE shapes=29 same=19 diff=0 over_accept=0 both_reject=10 aot_only_red=0 run_red=0 both_err_diff=0 repo_build_residue=0，ELAPSED=70s = 2.4 s/形
# 注册读数（v2 全量，脚本 md5 69806529…）：C010J_DONE shapes=23 same=16 diff=0 over_accept=5 both_reject=2 aot_only_red=0 run_red=0 both_err_diff=0 repo_build_residue=0，ELAPSED=77s
# 跨 run 复证（2026-10-08 第二轮，同脚本同代次）：汇总列逐项等值，表 md5 6d4dc390… → 把 ELAPSED 归一回 77s 后 = 登记值 8b208dd0… ⇒ 除耗时行外逐字节全等
#   ★ 入库状态：v2 表已入 HEAD（`git show 73f4d6b:fuzzy_scripts_720/tmp/c010_alt_syntax_gate_tmp.tsv` ⇒ md5 `6d4dc390…`）；v3 脚本与表**尚未提交**⇒ 复跑前以脚本 md5 自证代次，勿凭文件存在性判断
# 判读（v3 口径）：same=19 ⇒ 正例面（含 3 枚 elseif/else 多语句臂，守住改动 2）；over_accept=0 ⇒ 宽容面已消；both_reject=10 ⇒ 十枚负例与 PHP 同拒；
#   ★ aot_only_red 与 run_red **必须恒为 0**：任一转正即「替代语法从可用变不可用」的真回归（本门唯一的硬守卫列）
#   ★ diff 判据是「AOT 与 PHP 输出逐字节等值」⇒ 与 §3.5 的 H2 判读口径同源：本门**不比谁语义更对**，只比接受/拒绝边界
# R-3 落地实测（2026-10-09，旗标 `Parser.strict_alt_closers` 只由 AOT 入口置位）：预测 `over_accept 5→0` **达成**、
#   `both_reject 2→7` 按 23 形口径给的而实测 10（= 旧 7 + v3 新增 3 枚负例，无缺一枚）、`aot_only_red=0` **守住**；
#   预测里「`same=16` 不变」**不足以保证零误拒**（旧 16 形全为单语句臂 ⇒ 必须补 3 枚多语句臂才算验收，见 §3.6「预测偏差的根因」）
# 尚未收口的 P2 消息面：10 枚同拒里 4 枚（`n_endif_alone`/`n_colon_brace_mix`/`n_double_endif`/`n_else_no_endif`）AOT 报通用句
#   `Unexpected token in expression` 而非 PHP 的 `unexpected token "endif" …` ⇒ 不经 `tagToExpected`，另一条报错支
# 修门提醒：**v1（脚本 4009de13…／表 a8afda22…）的数据列禁止引用**（`tr '\n' '|'` 撑破列契约 ⇒ n_* 行 NF=9），
#   其四列 key（shape/php_rc/aot_rc/verdict）仍可与 v2 逐行对照 ⇒ 已实证 23/23 全等，修门未扰动判据
# 语料面复扫（分词器口径，判据 3/4；pass 目录实测输出 3 行：root/php_files、close 计数、alt 开口头 + 花括号头计数）：
timeout 30 /opt/homebrew/bin/php fuzzy_scripts_720/tmp/c010j_alt_corpus_scan_tmp.php fuzzy_scripts_720/pass
# 预期：close_marker_tokens_at_syntax_position=0 / alt_syntax_headers=0 ⇒ 冻结基线对本面零保护；
#   一旦两值同时 >0 ⇒ 语料已新增替代语法用例，本门从「守卫门」升级为「验收门」

# 永久侧门 K（花括号 switch 与 case 臂族，24 形 = 正例 14 + 负例 10，实测 42s = 1.8 s/形；必须在仓库根执行）
timeout 300 bash fuzzy_scripts_720/tmp/c010_brace_switch_gate_tmp.sh
# 注册读数（v1 全量，脚本 md5 6408a6b6…／表 md5 b3eb6e91…，代次 二进制 81f8a55a… / parser 5ad452fe…，零 src/ 改动）：
#   C010K_DONE shapes=24 same=8 over_accept=4 diff_php_ok=1 both_reject=6 aot_only_red=5 run_red=0 repo_build_residue=0 SMOKE_ONLY=0
# 跨 run 复证：注册表 vs 首轮快照（c010k_presnap/，md5 6f4e9f8b…）去掉 ELAPSED 行后 diff ⇒ **diff_rows=0**
# ★★ 本门自建成起即为「验收门」而非「守卫门」：aot_only_red=5 非 0（= 面孔 B 的五枚 `case`/`default` 分号臂假拒绝，
#    见 §3.7）⇒ **禁止把该列读成本轮新增回归**；修复验收位为 over_accept 4→0 且 diff_php_ok 1→0，
#    同时 aot_only_red 5→0（面孔 B 收口）；两枚硬守卫列 run_red 恒 0、repo_build_residue 恒 0
# ★ 面孔 A（4 枚 OVER_ACCEPT）里 `k_stray_endswitch` 非空输出而是**照跑并打 `z`** ⇒ 只盯「空输出=静默」的判据会漏它
# 面孔 C 的六枚补充形未进门（需 AST 侧先定形态）⇒ 逐形读数见 §3.7 表，复测为一次性 `/tmp` 探针、仓库根执行
# 语料面复扫（分词器口径，判据 3/4；两枚独立扫描器互证 switch/花括号/替代头三列）：
timeout 90 /opt/homebrew/bin/php fuzzy_scripts_720/tmp/c010k_brace_switch_corpus_scan_tmp.php fuzzy_scripts_720/pass
# 预期（pass）：files=68 switch=4 brace=4 alt=0 stmt_before_first_case=0
timeout 90 /opt/homebrew/bin/php fuzzy_scripts_720/tmp/c010k_case_order_terminator_scan_tmp.php fuzzy_scripts_720/pass
# 预期（pass）：files=68 switch=4 brace=4 nonlast_default=0 semi_arm=0 colon_arm=20
#   ★ 三列全 0 = 三面孔语料内零暴露 ⇒ 冻结基线零保护力；一旦非 0 即说明语料新增了受面构造，须重估落地风险
#   ★ scanner ② 为 **v2**（v1 把 enum/match 全记为 switch 臂 ⇒ semi 假阳性 87，数据列禁止引用，见 §3.7 修 scanner 记录）
#   必过控制臂（v2 内置，任一失配即 scanner 坏）：match `default =>` 与 enum 带值 case 不得记 SEMI；
#     合成形 `switch(1){case 1;}` 必须记 SEMI；嵌套 switch 的外层 default 在末臂时不得记「非末臂」

# 永久侧门 L（switch 臂表位邻形，23 形 = 控制臂 4 + 邻形 19；R-5 落地前置守卫门；必须在仓库根执行）
timeout 300 bash fuzzy_scripts_720/tmp/c010l_switch_armslot_gate_tmp.sh
# 注册读数（**落地前**快照，脚本 md5 babe0877…／表 md5 8a0116db…，代次 二进制 81f8a55a… / parser 5ad452fe…）：
#   C010L_DONE shapes=23 same=9 over_accept=6 diff_php_ok=0 both_reject=7 aot_only_red=1 run_red=0 ELAPSED=50s（2.2 s/形）
# R-5 的验收位（实测达成，读数见 §3.8.4）：over_accept 6→0、aot_only_red 1→0（后者为 R-3 批漏网形 l_alt_semi_arm）
# ★ 表头内嵌「case 列表首恰好接受一枚空语句分号」的实测规则（php 8.5.8）⇒ 本门是 R-5 形态的**唯一来源**，
#   复跑或改形时必须先回显该规则；引用行号一律按 §3.8.6 的当代次锚点（旧 :3571/:3583/:3611/:3616 已漂移）
# 必过控制臂（9 枚，逐字节不得变）：l_ctl_case_first / l_ctl_default_first / l_ctl_empty / l_ctl_between_arms /
#   l_semi_arm_list / l_semi_only / l_case_before_default / l_nested_brace_inner / l_semi_between_arms
# ★ 面 B/C 的形**不在本门**（属 AOT-CODEGEN-011）⇒ 本门 aot_only_red 恒 0；若出现非 0 即为**本单新增回归**，须停下归因
```

**R-2 批落地后实测读数（2026-10-07，分叉旗标门控 = D-2 裁决口径，替换上方「三模式同修」旧预期）**：
```bash
# 门 E：C010KW_DONE shapes=19 same=19 diff=0 silent_empty=0 aot_fatal=0 compile_fail=0
# 门 F：C010MECH_DONE shapes=8 same=8 diff=0 zero_instr=0 compile_fail=0（m_true_upper gvar 列已转 none）
# 门 G：C010G_DONE shapes=7 same=7 diff=0 red_confirmed=0 guard_same=4 guard_red=0
# 门 H：C010H_DONE shapes=79 arms=200 face=1 noface=73 confounded=5 bad_probe=0 ctrl_compile_fail=1
#              probe_compile_fail=0 probe_timeout=0 inverse_shapes=21 inverse_face=1 inverse_noface=20
#              inverse_confounded=0 repo_build_residue=0 SMOKE_ONLY=0
#       残面归属：face=1 → k_unset（调用名解析独立缺陷）；inverse_face=1 → invf_go（外族词运行碰撞）——见 §8
# 门 H2：C010H2_DONE shapes=15 over_accept=14 strict_same=1 aot_compile_fail=0 php_ok_aot_diff=0（不变）
# 门 I：C010I_DONE shapes=19 tree_same=7 tree_diff=12 bc_same=7 bc_diff=12 aot_same=19 aot_diff=0
#              aot_compile_fail=0 both_red=0 vm_only_red=12 aot_only_red=0 repo_build_residue=0 SMOKE_ONLY=0
#       ★ D-2 分叉判据：tree/bc 四项读数必须与修复前注册值逐项相同（12 枚红面按裁决保留在 VM 侧）；
#         vm_only_red 由 1→12 是 AOT 全绿后的分类位移（11 枚 both_red 并入），非 VM 侧新增
# 影子：C010_SHADOW_DONE total=68 same=68 diff=0 miss=0（冻结基线零漂移）
# 主回归：Total=68 / Pass=67 / Skip=1（f004，基线保持）
```

**R-3 批落地后实测读数（2026-10-09，代次 `parser.zig` `5ad452fe…` / 二进制 `81f8a55a…`；链 `fuzzy_scripts_720/tmp/c010_r3_acceptance_chain_tmp.sh` = 六门 → 主回归 → 影子；逐门读数与逐行等值取证见 §3.6）**：
```bash
# 门 E：C010KW_DONE shapes=19 same=19 diff=0 silent_empty=0 aot_fatal=0 compile_fail=0（19 行 diff_rows=0，ELAPSED 69s）
# 门 F：C010MECH_DONE shapes=8 same=8 diff=0 zero_instr=0 compile_fail=0（8 行 diff_rows=0）
# 门 G：C010G_DONE  shapes=7 same=7 diff=0 red_confirmed=0 guard_same=4 guard_red=0 compile_fail=0（7 行 diff_rows=0）
# 门 H：C010H_DONE shapes=79 arms=200 face=0 noface=78 confounded=1 bad_probe=0 ctrl_compile_fail=0
#              probe_compile_fail=0 probe_timeout=0 inverse_shapes=21 inverse_face=0 inverse_noface=21
#              inverse_confounded=0 repo_build_residue=0 SMOKE_ONLY=0（103 数据行 diff_rows=0，ELAPSED 738s）
#       ★ 与 §3.4.6 的 R-2 落地代读数（face=1 noface=73 confounded=5）不同属**代次差异**：
#         §8 六枚缺陷（#1/#2/#4/#5/#6/#7，任务 #122/#123/#124 代次）已把 k_unset、invf_go 等面收掉 ⇒ 本行为 §7 状态行登记的终态
# 门 H2：C010H2_DONE shapes=15 over_accept=12 strict_same=1 aot_compile_fail=2 php_ok_aot_diff=0（ELAPSED 46s）
#       ★ 变动列 = over_accept 14→12 / aot_compile_fail 0→2，逐形定位为 `n_endif`/`n_endswitch`（关闭标记位）**与 PHP 同拒**
#         ⇒ 收敛而非回归；本门汇总列无 BOTH_REJECT 桶 ⇒ 引用前必须回读逐形列的 php_rc 判向（判据见 §3.6）
# 门 I：C010I_DONE shapes=19 tree_same=7 tree_diff=12 bc_same=7 bc_diff=12 aot_same=19 aot_diff=0
#              aot_compile_fail=0 both_red=0 vm_only_red=12 aot_only_red=0 repo_build_residue=0（19 行 diff_rows=0，ELAPSED 69s）
#       ★ D-2 分叉判据达成：tree/bc 与注册值逐项相同 ⇒ 严格闭合只落在 AOT 侧
# 门 J：C010J_DONE shapes=29 same=19 diff=0 over_accept=0 both_reject=10 aot_only_red=0 run_red=0（ELAPSED 70s，见上「注册读数」）
# 门 D8（§8 家族验收面，链毕后串行补跑，timeout 300 bash fuzzy_scripts_720/tmp/c010_indep_defects_gate_tmp.sh）：
#       C010D8_DONE shapes=14 defect_red=1 guard_same=13 compile_fail=0 bad_probe=0 repo_build_residue=0 ELAPSED=49s
#       逐行与上一代次快照零差异 ⇒ 本批对 §8 面零扰动；★ 首轮与影子门并发所得 residue=1 **禁止引用**（并发污染，见 §3.6）
# 主回归：Total=68 / Pass=67 / Skip=1（f004）；影子：total=68 same=68 diff=0 miss=0 ELAPSED=1585s（冻结基线零漂移）
```

**R-5 批落地后实测读数（2026-10-09，任务 #127，面孔 A 花括号 `switch` 臂表位严格化 + 永久侧门 L 建成；代次 `parser.zig` `1eab26c068b13b9f904d2f432464d852`／4305 行 ／ 二进制 `6939cd2e891f20aef590de2585b15681`，`lexer.zig` `e3dd4191…`／543 行与 `keyword_lookup.zig` `ef70993a…`／186 行**未动** ⇒ 零词法面扰动；链 `fuzzy_scripts_720/tmp/c010_r5_acceptance_chain_tmp.sh` = K→L→J→D8→E→F→G→H→H2→I → 主回归 → 影子，全链 `repo_build_residue=0`、`SMOKE_ONLY=0`）**：
```bash
# 门 K（§3.7 验收门，★ 硬守卫列非 0 属面 B/C，禁止当新增回归）：
#       C010K_DONE shapes=24 same=8 over_accept=0 diff_php_ok=1 both_reject=10 aot_only_red=5 run_red=0（ELAPSED 31s）
#       ★ 变动列 = over_accept 4→0（面 A 四枚转 BOTH_REJECT）；aot_only_red 恒 5、diff_php_ok 恒 1
#         ⇒ 面 B（`case expr;` 五枚假拒绝）与面 C 零扰动，逐字与 #126 取证代次相同
# 门 L（本轮新建，`switch` 臂表位邻形 23 形，面孔 A 的守门位）：
#       C010L_DONE shapes=23 same=10 over_accept=0 diff_php_ok=0 both_reject=13 aot_only_red=0 run_red=0（ELAPSED 33s）
#       ★ 落地前注册值 same=9 over_accept=6 aot_only_red=1（那枚红 = R-3 批漏网形 `l_alt_semi_arm`）
#         ⇒ 本门同时收了 R-3 的第 2 张面孔，A 旗标位与臂表位邻形两套形集必须并存（见 §3.8）
# 门 J：C010J_DONE shapes=29 same=19 diff=0 over_accept=0 both_reject=10 aot_only_red=0 run_red=0 both_err_diff=0（29 行 diff_rows=0，ELAPSED 66s）
# 门 D8：C010D8_DONE shapes=14 defect_red=1 guard_same=13 compile_fail=0 bad_probe=0（14 行 diff_rows=0，ELAPSED 47s）
# 门 E：C010KW_DONE shapes=19 same=19 diff=0 silent_empty=0 aot_fatal=0 compile_fail=0（19 行 diff_rows=0，ELAPSED 65s）
# 门 F：C010MECH_DONE shapes=8 same=8 diff=0 zero_instr=0 compile_fail=0（8 行 diff_rows=0，ELAPSED 26s）
# 门 G：C010G_DONE shapes=7 same=7 diff=0 red_confirmed=0 guard_same=4 guard_red=0 compile_fail=0（7 行 diff_rows=0，ELAPSED 24s）
# 门 H：C010H_DONE shapes=79 arms=200 face=0 noface=78 confounded=1 bad_probe=0 ctrl_compile_fail=0
#              probe_compile_fail=0 probe_timeout=0 inverse_shapes=21 inverse_face=0 inverse_noface=21
#              inverse_confounded=0 repo_build_residue=0 SMOKE_ONLY=0（100 行 diff_rows=0，ELAPSED 700s）
# 门 H2：C010H2_DONE shapes=15 over_accept=12 strict_same=1 aot_compile_fail=2 both_reject=2 aot_only_red=0
#               php_ok_aot_diff=0 repo_build_residue=0 SMOKE_ONLY=0（15 行 diff_rows=0，ELAPSED 45s）
#       ★ 与 R-3 代次逐字节相同 ⇒ 本批旗标只作用在 `switch` 臂表位，未触碰关闭标记位
# 门 I：C010I_DONE shapes=19 tree_same=7 tree_diff=12 bc_same=7 bc_diff=12 aot_same=19 aot_diff=0
#              aot_compile_fail=0 both_red=0 vm_only_red=12 aot_only_red=0 repo_build_residue=0（19 行 diff_rows=0，ELAPSED 66s）
#       ★ D-2 分叉判据第 2 次达成：tree/bc 与冻结注册值逐项相同 ⇒ `strict_switch_case_list` 只落在 AOT 侧
# 主回归：Total=68 / Pass=67 / Fail=0（三档全 0）/ Skip=1（f004，PHP_error_exit=255），regression_rc=0（12m54s）
# 影子：C010_SHADOW_DONE total=68 same=68 diff=0 miss=0 ELAPSED=1507s（25m07s，冻结基线零漂移）
# 逐行等值比对器 c010_r5_rowdiff_tmp.sh（腿后复测）：K=8 行 / L=24 行为**预期变动面**（K 的 4 枚 OVER_ACCEPT 转拒 ⇒ 4×2；
#       L 为新建门 ⇒ 全表换判向），其余九腿（J/D8/E/F/G/H/H2/I/影子）**diff_rows=0**（影子 136/136）
# 全链墙钟 56m24s（12:21:51 → 13:18:15）= 十门 18m23s（Σ ELAPSED 1103s，双向互证）+ 主回归 12m54s + 影子 25m07s
# zig build test：21/21 steps succeeded、326/326 tests passed
```

**复测纪律（实测仅门 H / H2 / I 含 `ONLY=` 冒烟通道；门 E/F/G 经 `grep -c ONLY` 实测**无**该通道）**：`ONLY=` 冒烟通道写入的是**独立的** `*_smoke_tmp.tsv`，其总数行带 `SMOKE_ONLY=1` ⇒ **禁止当作全量读数引用、用完必须删除**（门 I 首跑的「smoke 里装了全量」、门 H 反例组的 3 形冒烟、以及归因轮里曾用临时脚本产生的假 `zero_instr=8` 三坑同源；注册读数一律取自无 `ONLY` 的全量跑）。

---

## 7. 遗留 / 待裁决 / 流程项

1. ~~八枚红形的下游失败点未逐形归因~~ **已由 R-1 闭环（任务 #119）**：五类断点逐类到行（§3.1），A 类零指令 / B 类差一对括号 / C 类语句层臂表缺项 / D 类落点在守卫之外 / E 类两处缺陷互抵消 ⇒ 「R-2 一枚改动可能只消部分面」这一疑虑已被**实测收窄**：A/B/C/D 四类**同源于 lexer 一枚根**（D 类只是文法位不同 ⇒ 落在守卫外），故 R-2 可一次消四类；**唯一消不掉的是 E 类的第二张面孔**（常量表动态查名，源码内无大写关键字 ⇒ 必须并批 R-2b，见 §3.3）。
2. ~~混合大小写关键字族的覆盖面未穷举~~ **已由永久侧门 H 闭环（任务 #120）**：按 `keyword_lookup.zig` **87 枚表项**自动生成 79 形（87 − 7 枚外族词走反例组 − 1 枚 `yield` 属宪法 §七-1 排除项），一形一文件、双臂只差拼写，实测 `ELAPSED=595s`（**100 形含 21 形反例组 = 6.0 s/形**）⇒ 覆盖面从 E 的 19 形扩至 79 形、红面从 11 枚扩至 **59 枚**。逐类读数与三分文法位见 §3.4.1，过度识别名位矩阵见 §3.4.2。
3. ~~**`len <= 15` 硬编码上限**（`lexer.zig:390`/`:394`）：属宪法 §四-3 的存量违反，登记待与 R-2 并批（R-4）~~ **已由 R-4 闭环（2026-10-09 本轮 grep 实测锚点，原行号已漂移）**：查表上限不再是字面 15，`lexer.zig:405` 走 `text.len <= keyword_lookup.max_key_len`，该常量由 `keyword_lookup.zig:104` 从表项**计算**得出，并有 `keyword_lookup.zig:184` 的回归钉 `expectEqual(@as(usize, 13), max_key_len)` 守护（实测最长键 13 字符 = `__NAMESPACE__`）⇒ 新增更长关键字时上限自动跟随，硬编码已消除。**本项原判「仅剩 2 字符余量」的风险随 R-4 一并消解**（原始实测见 §3.4 表与 §7-11）。
4. ~~跨模式是否一并修（证据仅 4 形定性）~~ **已由永久侧门 I 量化（任务 #120，19 形 × AOT/tree/bytecode）**：实测 `aot_only_red=0`、`both_red=11`、`vm_only_red=1`（见 §2.2）⇒ **不存在「只修 AOT 即可关掉的形」**，且本单根因在三模式共享的编译前端 ⇒ 需老铁裁决的问题已收窄为「**是否接受 R-2 天然三模式同修**」（宪法 §五 的形式要求由实测替代：无法只动 AOT 一侧，除非分叉前端）。
5. **`--compile` 解析失败仍返回 0 且不产出二进制**：本面使官方门若只看 exit 码会把「编译失败」读成「运行成功但无输出」。属**测试流程**问题而非编译器语义，建议单列（与 RUNTIME-002 §7-4 的 skip-before-compile 流程项同族，可并批讨论）。
6. ~~`TRUE`/`FALSE`/`NULL` 为何免疫~~ **已闭环并改判为「非免疫」（任务 #119）**：成因 = 大写失配 → `.variable "TRUE"` → `getGlobalVar("TRUE")` → 命中运行期**大写单拼写键**内置常量表（`runtime_lib_template.zig:7614/:7615/:7637`）⇒ 与 lexer 缺陷**互抵消**才呈 SAME。⇒ 原设想「用它当 R-2 的实现先例」**不成立**（它不是大小写不敏感通道，前端仍是零先例）；反之发现该表自身是**第二处独立缺陷**（§3.3 / R-2b）。
7. **C 类无生成码侧读数**：侧门 F 的 8 形全为可编译形 ⇒ C 类的断点（`parser.zig:496 else =>` 后接 `:2747 parseUnary` 无臂）来自「侧门 E 的 `compile.log` 错误文本 + parser 实文核对」，**未取 AST 侧行级读数** ⇒ 若 R-2 落地后 C 类三形仍红，需另开 AST 探针轮。
8. **D 类 `reg_5` 跳号属推断**：实测事实 = 生成码内 `reg_4`（then 串）之后直接是 `reg_6`（else 串），`reg_5` 全文 0 次出现；「`ELSE` 语句占用了 IR 寄存器号却未发射任何指令」是对该跳号的**推测解释**，未经 IR 侧取证 ⇒ 禁止在 R-2 落地评审中当证据引用。
9. **侧门 F / G / H / H2 / I 五张为本轮新建资产**：尚未纳入官方十二腿门链，且与本轮全部工单文档同样**未提交**（待老铁「提交」指令）；五门总数已按「先修门、后引用」口径只登记修正后读数（H 的两轮修门见 §7-11）。**2026-10-08 追加第六张 = 侧门 J（§3.6，替代语法正/负例）**，处置口径相同：未入库、未纳官方门链、v1→v2 两轮读数按「先修门后引用」登记 ⇒ **D-7 的问询范围现为十门**。**2026-10-09 追加第七张 = 侧门 K（§3.7，花括号 `switch` 与 `case` 臂族，任务 #126）**，处置口径相同（未入库、未纳官方门链），但**判读口径不同**：门 K 自建成起即为**验收门**（硬守卫列 `aot_only_red=5` 非 0，= §7-15e 的面孔 B）⇒ **D-7 的问询范围随之 +1**，且引用本门时禁止把该列当新增回归。**2026-10-09 追加第八张 = 侧门 L（§3.8，`switch` 臂表位邻形 23 形，任务 #127 与 R-5 同批建成）**，处置口径与 K 相同（未入库、未纳官方门链），但**判读方向与 K 相反**：L 的硬守卫列 `aot_only_red` **必须恒 0**（非 0 即本单新增回归，须停下归因），面孔 B/C 的形刻意**不在本门** ⇒ **D-7 的问询范围随之扩至十一门**。L 的表头内嵌「case 列表首**恰好接受一枚空语句分号**」（php 8.5.8 实测：`l_semi_arm_list`/`l_semi_only`/`l_alt_semi_arm` 为 rc=0，`l_two_semi_*`/`l_semi_then_block` 为 rc=255）⇒ 该规则是 R-5 落地形态的**唯一来源**，改形或复跑前必须先回显；另外 L 首跑（落地前）曾以 `aot_only_red=1` 抓到 R-3 批的漏网形 `l_alt_semi_arm` ⇒ **新教训＝「只覆盖关闭标记位的门不覆盖臂表位邻形」**，A 旗标位形集与臂表位形集必须并存。
10. **`parser.zig:3756-3759 isKeywordUsableAsIdentifier` 是恒返回 `false` 的死桩**（任务 #120 只读发现）：文档注释写「any keyword that can be used as method/property name after -> or ::」，但函数体 `return false;`，且**全树零调用点**（真实能力在同文件 `:3761 isKeywordIdentifierTag` + `:3843 eatKeywordAsIdentifier`，8 处名位调用）。⇒ 属宪法 §四-2「禁止打桩/stub 跳过真实逻辑」的**存量**违反，且对后续读码者是**误导源**（会以为名位不容忍关键字，而语料 45 处 `->get/->set/->lock` 全靠该容忍支才绿）。⇒ **删除或改名均需 §六 点头（涉及删除代码）**，本轮只登记；与 §5 的 R-2/R-4 不同批（不属大小写面孔，动它=纯注释/死码卫生）。
11. **侧门 H（87 枚表项穷举门）已建并两轮修门后闭环**（任务 #120）：`fuzzy_scripts_720/tmp/c010_kw_full_table_gate_tmp.sh` ⇒ `c010_kw_full_table_tmp.tsv`。逐形双臂（同模板只差拼写）+ 过度识别反例组。**两轮修门均为「先修门、后引用」**：① `k_callable` 坏探针（Go 风格 `fn(): int {}` 被 PHP 自己拒）⇒ 补 `php -l` 预检 + `BAD_PROBE_*` 两类，读数 `face 58→59`、`confounded 6→5`、`bad_probe=0`；② 反例组旧版 7 形各用**不同名位** ⇒ 「`get`/`set` 绿」实为方法名位的功劳而非该词无害（**已由 3 形冒烟实测证实同一词的函数名位/类名位红、方法名位绿**）⇒ 形集改为 **7 词 × 3 名位 = 21**。两版首跑读数均**禁止引用**，注册读数取自最终全量跑（§3.4）：`C010H_DONE shapes=79 arms=200 … inverse_shapes=21 inverse_face=15 inverse_noface=6 inverse_confounded=0 repo_build_residue=0 SMOKE_ONLY=0` / `ELAPSED=595s`，且主群 79 行跨 run `diff_bytes=0` ⇒ 修门未扰动主群。
12. **五枚与大小写无关的默认档独立缺陷是否立单（待老铁裁决）**：`k_and`（括号操作数组内 `and` 求值错、静默 rc=0）、`k_var`（`var` 属性声明编译失败）、`k_goto`（`goto` 形使尾部整体消失）、`k_iterable`（`iterable` 拒绝数组 + 消息内 `$$a` 双 `$` 渲染）、`m_namespace`（`__NAMESPACE__` 在 `namespace` 声明后取空串）。⇒ 逐枚**不属于**本单 lexer 根，R-2 不消（§3.4.3）⇒ 按宪法 §五「不扩散」原则本轮只登记；若要修需另立工单（`var`/`goto`/`and` 三枚属解析与求值面，`$$a` 属消息渲染面）。
13. **AOT 重复警告行（新观察，未归因）**：同一未定义变量 AOT **连打两行** —— `Warning:  Undefined variable True`（双空格）与 `Warning: Undefined variable True`（单空格），PHP 只打一行 `PHP Warning: …`。出现在门 H 全部含 `Undefined variable` 的红面行，小写臂不出现 ⇒ 与本单根因无关，疑为警告发射点重复（登记待归因，优先级 P2；因其污染等值判据，**任何以「输出逐字节等值」为准的门都会因此多算红**）。
14. **返回类型声明校验面无工单归属**：§3.5 三枚类型形（`void`/`mixed`/`object`）证明 AOT 对**未知/非规范拼写的返回类型名不校验**（PHP 侧 Fatal）。⇒ ①「AOT 对**已知**返回类型（`: int` 等）是否校验」**本门未测**；② 已核对 `AOT-TYPE-001` = PHI 节点类型混接、状态 CLOSED ⇒ **不覆盖**本面；③ 近邻仅 `AOT-RUNTIME-002` G4 的 typed 槽六面（静态属性侧）。⇒ 若要定面需**另立门/另立单**，禁止由本表外推。另 `n_never` 为**永久零判别力**形（PHP 对只 `throw` 的 `: never` 体不报错 ⇒ 无对照可选），登记于此而非门缺陷。
15. ~~替代语法（`if:`…`endif;` / `switch:`…`endswitch;`）是否真被支持仍不可判~~ **已由永久侧门 J 闭环（2026-10-08，任务 #123 建门并实测；详见 §3.6）**：正/负例 23 形实测 `shapes=23 same=16 diff=0 over_accept=5 both_reject=2 aot_only_red=0 run_red=0 ELAPSED=77s` ⇒ **判为「真支持」**（16 枚正例逐字节等值 + 旧语料 `fuzzy_scripts/test_006/007/008` 三枚真实脚本内含 5 枚替代语法构造亦 3/3 等值），五支 `is_alternative` 支路产出标准 AST 节点 ⇒ 发射侧语法无关。**代价是新立一张面孔**：5 形 **OVER_ACCEPT**（缺 `endif;`、缺 `endswitch;`、异种 `endwhile`、顶层裸 `endif;`、双 `endif;` ⇒ PHP rc=255 而 AOT rc=0 且静默），分界实测为**关闭标记消耗软硬不对称**（`if :1515-1517`／`switch :3563-3565` 软，`while :1581`／`foreach :1672`／`for :1833` 硬）+ `:1594` 体扫描只认同种 end 标记 + `:3299-3305` 旗标容忍支把多余 `end*` 降级成变量语句。语料面按分词器实测为 **0**（`pass/`68、`fail_runtime/`77、`fail_compile/`12 的开口头与关闭标记全 0；32 处粗筛命中全在字符串/注释内）⇒ 判据 3/4：正例与负例**都不受冻结基线保护**，但机制完全可达。**修复已于 2026-10-09 落地（老铁裁决＝「A 旗标门控，只改 AOT」＋「只做门 J P1」）**：新增 `Parser.strict_alt_closers`（仅 `initWithModeInsensitive`＝两枚 AOT 入口置位，解释器/字节码构造点恒 `false`）⇒ 软消耗改硬 `eat` + 体扫描遇异种 `end*` 终止 + 五枚关闭标记排除出表达式主位容忍支 + `switch` 意外 token 不再整枚跳过 + `tagToExpected` 补 5 枚 `end*` 臂。**门 J v3 终态读数（29 形，`ELAPSED=70s`）**：`same=19 diff=0 over_accept=0 both_reject=10 aot_only_red=0 run_red=0 both_err_diff=0` ⇒ 5 枚宽容面**清零**、正例面（含 3 枚新补的 elseif/else 多语句臂）与真实语料 3 枚全绿、两枚硬守卫列仍为 0。逐处锚点、预测偏差根因与 P2 消息面残差见 §3.6「R-3 批落地实测」。
15b. **门 J 自身读数代次（先修门、后引用）**：v1（脚本 `4009de13…`／表 `a8afda22…`）有两个门缺陷 —— `tr '\n' '|'` 与列分隔符冲突致报错行 NF=9 撑破 7 列契约、compile_fail 支未记录 AOT 原文 ⇒ **v1 数据列禁止引用**；v2（脚本 `69806529…`／表 `8b208dd0…`）修复并复跑，`(shape, php_rc, aot_rc, verdict)` 四列与 v1 **逐行全等 23/23** ⇒ 修门未扰动判据。附带发现：`tagToExpected:220-235` 无任何 `.k_*` 臂（兜底 `else => "token"`）⇒ 硬 `eat` 的期望词名不如 PHP 精确，P2 消息面（**R-3 批已补 5 枚 `end*` 臂 ⇒ 本附带发现的「无任何 `.k_*` 臂」仅对 v2 代次成立**）。v3（脚本 `592ef974…`／表 `2a25520c…`／29 形）为 R-3 落地轮，形集只加不改判据 ⇒ 与 v2 的等值对照用**逐形 join**（把 v2 表 `git show 73f4d6b:…tsv` 与 v3 表都折叠成 `(shape, verdict)` 后排序对齐，实测 23 枚共有形全覆盖）：**16 枚 `p_*` 全部 SAME→SAME**（正例面零扰动）、**5 枚 `OVER_ACCEPT` 全部转 `BOTH_REJECT`**（即本轮验收位）、2 枚原 `BOTH_REJECT` 保持；v3 新增 6 形落位为 3 枚 `p_*`（elseif/else 多语句臂）SAME + 3 枚 `n_*` BOTH_REJECT。
15c. **残留宽容面（R-3 批落地后实测，2026-10-09）＝花括号 `switch` 在首个 `case` 前的裸语句仍被 AOT 静默接受**：`switch (1) { echo "W"; }` ⇒ PHP `php -l` **rc=255** `syntax error, unexpected token "echo", expecting "case" or "default" or "}"`；AOT **rc=0 且空输出**（产物可执行）。对照同位邻形 `if (1) { echo "A"; `（缺 `}`）⇒ 两侧同拒（AOT `unexpected end of file, expecting "}"`）。根因＝改动 5 的 `break` 条件写成 `is_alternative and strict_alt_closers`（`:3595`），**花括号支保留旧的 `self.nextToken(); // Skip unexpected tokens`** ⇒ 与 `n_switch_stmt_before_case_alt`（替代语法支，已 `BOTH_REJECT`）为同码位**两面孔**。**未扩面的理由＝本轮裁决口径「只做门 J P1」＋`is_alternative` 门控可保证对 68 语料的花括号 `switch` 零扰动**；若要消这枚需 §六 另行点头（改动点同 `:3595`，判据要加 1 枚花括号形进门，且必须重跑影子 ⇒ 花括号 switch 是语料高频构造，风险面远大于替代语法）。⇒ 当前门 J 的 10 枚负例**不含**此形，登记于此后不得当作已收口。**【2026-10-09 任务 #126 取证收口】**该面已由**新门文件**（永久侧门 K，禁扩已注册门 J）量化至 **4 枚 OVER_ACCEPT**（不止本枚：`k_stmt_before_case`/`_two`/`k_nested_stmt_head` + `k_stray_endswitch`，末枚非空输出而是**照跑并打 `z`**），且「对 68 语料零扰动」那句里的旧推断已**升为实测**：两枚独立分词器扫描器互证 `stmt_before_first_case=0`（全语料 249 文件、7 枚 switch 全花括号头）⇒ 合法代码永不进入 `:3592` 的 `else` 支。逐形读数、机制锚点与落地表单见 **§3.7** 与 §5 路线 **R-5**（一行：`:3595` 去掉 `is_alternative and`；验收链沿用实测 56m33s）。⇒ **取证状态＝已收口；落地状态＝仍待老铁点头（§六-2 风险面：花括号 switch 为语料高频构造，影子必跑）**，本项在老铁裁决前不得判为已修复。**【2026-10-09 任务 #127 落地批＝面 A 已收口】**老铁「继续推进已知问题修复」授权下按**旗标门控 AOT-only** 形态落地 R-5：新旗标 `Parser.strict_switch_case_list`（`:38`，仅由 `initWithModeInsensitive` `:82` 置位）+ `parseSwitch` 的**单枚前导分号豁免支**（`:3601–3606`）+ 严格支（`:3612`）。⇒ 本项里「改动点同 `:3595`，一行」的表述**由实测否证并更正**（详见 §3.8.1：`case` 列表首**恰好接受一枚空语句分号**为 PHP 合法形，直改会把 `l_semi_arm_list`/`l_semi_only` 两枚今日绿形砸成硬守卫红）。验收实测：**门 K `over_accept 4→0`**（`same=8 diff_php_ok=1 both_reject 6→10`，`aot_only_red=5` 恒等＝面 B 未触碰）、**门 L `over_accept 6→0` 且 `aot_only_red 1→0`**（`same 9→10 both_reject 7→13`）；副产品＝R-3 批的漏网硬守卫红 `l_alt_semi_arm` 同批闭合（§3.8.5）。⇒ **面 A（本项）判为已修复**；**面 B／C 仍待 AOT-CODEGEN-011 的 D-1…D-4 裁决**（本项旧句「若要消这枚需 §六 另行点头」对 B/C 两面孔仍然有效）；全链读数与代次见 §3.8.4/§3.8.7 与 §5 R-5 行。
15d. **门 H2 自身读数代次（先修门、后引用，任务 #125，2026-10-09）**：初代（脚本 `8e11de20…`／99 行，四桶）与 R-3 代次读数 `over_accept=12 aot_compile_fail=2` **结构上不可判向** —— 拒绝支实测代码（入库 blob `73f4d6b:…sh:76-80`）只写 `php_rc=` 数字、AOT 侧文本固定 `<none>`，「收敛」与「真回归」压成同一枚计数，R-3 落地轮据此差点把 `aot_compile_fail 0→2` 读成新红（靠人工回读 `php_rc=255` 才判明，见 §3.6）。#125 修门＝补 `BOTH_REJECT`/`AOT_ONLY_RED_*` 分桶 + `aot_log=`（走与门 J `:54` 同口径的 `normlog()`）+ 表头 `parser_md5` + 运行侧硬守卫；**当代次注册（脚本 `582ca74d…`／116 行 → 表 `0663be8d…`，mtime 晚于脚本）**：`shapes=15 over_accept=12 strict_same=1 aot_compile_fail=2 both_reject=2 aot_only_red=0 php_ok_aot_diff=0` @44s；修门证明＝与 R-3 快照逐字节 diff **12 行**（表头 4 + 2 形重分类 4 + ELAPSED + 总数行），**判据数据行 13/15 逐字节全等**。⇒ §3.6「对既有 P1 建议的部分收口」登记的 12 枚 H2 宽容面（类型位/修饰位/声明位）现由 `aot_only_red` 恒 0 守卫，任何收口批若把它们砸成「PHP 通过而 AOT 拒」会立即转正。详见 §3.5.1。
15e. **门 K 新立面孔 B（反向面＝假拒绝，2026-10-09 任务 #126 实测）＝`case`/`default` 的分号终结符被 AOT 拒绝编译**：PHP 8.5 对 `switch (1) { case 1; echo "S"; }` 只打 `Deprecated: Case statements followed by a semicolon (;) are deprecated, use a colon (:) instead`，**rc=0 且臂体照常执行**；AOT **无产物**，原文一律 `Parse error: syntax error, unexpected ";", expecting ":"` ⇒ 门 K 硬守卫列 `aot_only_red=5` **非 0**（`k_case_semi`/`_fall`/`k_default_semi`/`k_case_semi_alt`/`k_case_semi_two_arms`，含一枚替代语法同位形）。根因到行＝`parser.zig:3571`（`case` 臂）与 `:3583`（`default` 臂）两处 `_ = try self.eat(.colon); // or .fat_arrow` **硬只认冒号**。**附带否证**：该处注释声称的「or .fat_arrow」实测**方向相反** —— `case 1 => echo` 在 PHP 自己就 rc=255（门 K `k_case_arrow` 判 `BOTH_REJECT`）⇒ 注释描述的合法面不存在，而真实合法的 `;` 面反被拒（登记为源码注释失效锚点，属宪法 §四-2 语义的注释误导，改动需 §六 点头）。⇒ **与关键字大小写无关 ⇒ 不并入 R-3/R-5 批**，**已另立 [AOT-CODEGEN-011](AOT-CODEGEN-011-switch-case-semicolon-terminator-and-default-arm-position.md) 面孔 B**（路线 **R-B1**；改动 = 两行，验收链可复用实测 56m33s；该单另列待裁决 D-1「前端共用 vs 旗标只改 AOT」）。语料面实测 **0**（`semi_arm=0`，全 249 文件；对照 `colon_arm=37` 证明扫描器有判别力）⇒ 判据 3/4：**不受冻结基线保护、机制完全可达**。逐形读数与扫描器修 v1→v2 记录见 **§3.7**。
15f. **门 K 新立面孔 C（语义面＝`default` 臂位次在 AST 层就不存在，2026-10-09 任务 #126 实测）**：门 K 唯一 `DIFF_PHP_OK_AOT_DIFF` 形 `k_default_first`（PHP `DC` / AOT `D`）扩测六形后定面（§3.7 表）⇒ 分界实测为「**`default` 是否位于末臂**」，与花括号/替代语法无关；后果有两重 —— ① default 体尾**不落进后续 case**（丢 fall-through，PHP 会执行）；② **末位 case 的体尾错落进 default**（`switch (2) { default: "D"; case 2: "C"; }` PHP `C` / AOT **`CD`**）⇒ 属「执行了 PHP 不执行的语句」，比丢输出更重。根因到行＝`parser.zig:3616` 的 `.switch_stmt = .{ .expression, .cases, .default }`（**default 不入 `cases` 序列 ⇒ 源码位次信息在 AST 层就丢失**）× `ir_generator.zig:3211-3221` 按 `case_blocks.items[i + 1]` 链 fall-through、`:3215-3217` 末臂才接 `default_block`、`:3236-3237` default 体尾**恒 `br merge_block`**。⇒ 修复面必须**三处同动**（AST 形态 + IR 链入 + 末臂判定），需先定 AST 形态、且要动宪法 §一 超大文件 `ir_generator.zig`（改前必须 grep 既有模式，禁止凭推测写代码）⇒ **已另立 [AOT-CODEGEN-011](AOT-CODEGEN-011-switch-case-semicolon-terminator-and-default-arm-position.md) 面孔 C**（路线 **R-C1** AST 形态 + **R-C2** IR 链入，跨模式面 **R-C3** 待该单 §五 裁决），成本列「**未实测**」（无既有验收链可套）。语料面实测 **0**（`nonlast_default=0`，全 249 文件；基线 4 枚花括号 switch 逐处回文核对 = default 末臂或无 default）⇒ 冻结基线**恰好只覆盖绿的那一侧**，判据 3/4 同 15e。
16. **R-2 的落地形态是否含「parser 名位补洞」（✅ 已裁决并落地，2026-10-07）**：老铁裁决 **D-1 = 甲**（R-2 与名位补洞同批）+ **D-2 = 分叉**（仅 AOT 生效，解释器/字节码保持现状，机制 = `case_insensitive_keywords` 旗标门控）+ **D-2b 未答按保守口径 = 旗标门控**（文件级分叉违反 DRY §二-2 不采用）。落地过程与实测见 §3.4.6 —— 首轮仅补编目的两处名位被门 H 反例组实测打回（守卫探针 `function Get()`/`class With` 转红），第二批扩至 15 处名位 + 第四面孔后 `inverse_face 15→1`、守卫探针全绿。原判据「`inverse_face` 不得变小」系 R-2-乙（只改 lexer）口径；甲批下变小来自旗标门控容忍支（词表本身未动，编译期同源保证），残红 1 枚归属外族词家族（§8）。
17. **裁决记录（2026-10-07，本单）**：**D-1 = 甲**（lexer + parser 名位同批，带 R-4 + R-2b + 扩展 6 tag）｜**D-2 = 不接受三模式同修，分叉前端（仅 AOT）**｜**D-3 = 五枚独立缺陷并入本单**（§8）｜**D-4 = 死桩 `parser.zig:3756-3759` 维持现状**（未删未改名）｜**D-5/D-2b/D-6/D-7 问询未获答复** ⇒ 按宪法 §五/§六 保守口径：D-5 字节码 VM popFast panic **不修**（登记）、D-6 维持 §7-5 登记、D-7 六门不入官方门链、**全程零提交**（未获「提交」二字）。
18. **第四面孔（R-2 落地中发现）**：AOT 编译入口的 include/require 检测在**两处源文本层**做大小写敏感匹配 —— `main.zig` needs_multi_file 检测（决定单文件/多文件路由）与 `dependency_resolver.matchKeyword`（依赖图建边）。`Include "x.php";` 等合法拼写漏检 ⇒ 误走单文件 ⇒ `include_stmt` 在单文件 IR 层无人消费 ⇒ 整句静默（门 H k_include/k_require 四形残面根因）。修法 = 两处折形（检测 haystack 折小写；matchKeyword 改 `eqlIgnoreCase`）。
19. **门 H 残面与已知边界的完整归属见 §8**（k_unset 调用名解析、invf_go 外族词碰撞、标签定义位、parseCallArg 未扩展、表达式位 include 过度接受）。

---

## 8. D-3 并入登记：与关键字大小写无关的默认档独立缺陷（老铁裁决 D-3 = 并入本单，2026-10-07；任务 #122 归因轮已逐枚到行）

**永久侧门 D8（本家族验收面）**：`fuzzy_scripts_720/tmp/c010_indep_defects_gate_tmp.sh`（md5 `d783085b04b76c50f1c8fb76c6eae7ae`）→ `c010_indep_defects_tmp.tsv`（现行 md5 `c0190fb83074cac8d53d0407241d6d07`）。
注册读数（三代演进）：**归因代（#122）`defect_red=7 guard_same=6 compile_fail=1`** → **修复代 #122b `defect_red=4 guard_same=10`**（#1/#2/#5 转绿）→ **修复代 #122c `defect_red=1 guard_same=13 compile_fail=0 bad_probe=0 residue=0 ELAPSED=48s`**（#4/#6/#7 转绿，**唯余 d3a=goto 发射侧子轮**；GUARD_SAME 控制臂全程未动）。
判读：修复哪枚 ⇒ 哪枚转绿，**未修复的必须保持红**（防静默回归 + 防修复批互相遮蔽）；GUARD_SAME 控制臂（d1c/d1d/d3b/d3h/d5b/d7b）**任何时刻不得转红**。
**修门记录（先修门、后引用）**：首跑（md5 `7b017c51…`，ELAPSED=138s）因**全部探针体漏写 `<?php` 开标签**而全表作废——纯 HTML 文件 `php -l` 照样通过（lint 抓不到），PHP 把源码当 inline HTML 原样吐出、AOT 编译出零语句程序 ⇒ 读数 `defect_red=10 guard_same=0` 全部禁止引用。修法 = 补开标签 + 新增 **BAD_PROBE_PHP_EMPTY** 预检（PHP 归一化输出为空即坏探针；教训⑨强化版：lint 通过 ≠ 可执行语义探针）。影子门脚本汇总 awk 同轮修复（`END` 关键字被误用作变量 ⇒ 汇总行历次静默死亡，数据行 136 行均完整）。

**七枚缺陷到行归因（#122 实测；d1/d7 两枚的机制在归因轮中被探针反转，禁止引用工单旧措辞）**：

| # | 缺陷 | 判别探针（门 D8 形） | PHP vs AOT | 到行根因（实测） | 路线草案 |
|---|---|---|---|---|---|
| 1 | ~~`and`/`or`/`xor` 低优先级逻辑符被赋值 RHS 吞掉~~ **✅ 已修复（#122b）** | `$r = 1 and 0; echo $r ? y : n` | 修复前 `y` vs `n` ⇒ 修复后同 `y` | **赋值 RHS 优先级双位点**：语句级 `parseAssignment`（parser.zig:1994）RHS 改 `parseExpression(4)`；循环内赋值/复合赋值臂（:2684/:2692）改 `parseExpression(next_p - 1)`（同 star_star 右结合惯例）。**首版修复曾被门 D8 打回**：截断后尾随 `and 0` 悬空、分号断言失败 ⇒ d1a/d1b 转 COMPILE_FAIL ⇒ 补「赋值节点之上的 and/xor/or 续接链」（族内 prec 4>3>2 左结合）后全绿。**归因反转**：`and` 求值本身正确（d1c/d1d 控制臂全同），旧措辞「括号操作数组内求值错」作废 | ✅ 已落地：链式 `$a = $b = 1 and 0`、xor、or 边界探针全绿 |
| 2 | ~~`var` 属性声明编译失败~~ **✅ 已修复（#122b）** | `class KwhV2 { var $p = 3; }` | 修复前 `3` vs 无产物 ⇒ 修复后同 `3` | `parseClassMember` 成员修饰符循环（parser.zig ~:904）补 `.k_var => modifiers.is_public = true`（PHP4 风格隐式 public）。归因时发现 R-2 后 `Var $p`（原靠类型位侥幸绿）同被拖红，本修复一并救回 | ✅ 已落地：d2a 与 `Var $q` 探针全绿；门 H k_var 行 `RUN(3|3)` NOFACE |
| 3 | **反向 goto 环状块图发射丢失**（d3a 红） | `$i=0; L: $i++; if($i<2){goto L;} echo $i` | `2` vs 空输出 | IR 层 goto **有** BasicBlock 实现（ir_generator.zig:737-738 → generateGotoStmt :3879 / generateGotoLabel :3905）且**前向 goto 实证有效**（d3j `if(true){goto FW;} echo "skip"; FW: echo 1;` 输出 `1` = 真实跳转）；反向（d3a）生成码实测：**标签块体（`$i++` 写回）整体丢失 + then 臂空 + echo 落入 else** ⇒ 缺陷在**发射器层**（#122d 子轮定论）：native_linker 的函数体发射是基于**索引区间的结构化渲染**（`buildControlFlowBoundaries` 把 cond_br 映射为 then/else/merge 下标区间），**无条件 br 到非相邻块没有 Zig 表示**（Zig 无 goto）⇒ 标签块内容被整体丢弃。IR 侧行为试验（generateGotoStmt 去除 goto_after、对齐 break/continue 惯用法）已被实测否证回滚——g1 探针显示标签块仍被发射器丢弃且原 fallthrough 形态反而退化 ⇒ 正确修复 = 发射器实现 **goto 形状**（前向：目标区间内联复制；后向：while(true) 包裹 + break 出口），属核心结构化渲染器改造 | 发射器 goto 形状子轮（改动面 = native_linker 函数体渲染；语料 goto 0 处 ⇒ 影子预期零漂移；P2） |
| 4 | ~~`iterable` 类型位拒绝数组 + 消息 `$$a` 双 `$`~~ **✅ 已修复（#122c）** | 门 D8 复用门 H ctrl 形 | 修复前 `2` vs Fatal ⇒ 修复后同 `2` | 双根因：① `checkSingleType`（runtime_lib_template.zig）**缺 `iterable` 分支**落到类名检查 ⇒ array 被拒 —— 补 `array or Traversable 实现`（`meta.implementsInterface("Traversable")`）；② `php_check_param_type` 消息格式串 `${s}` 主动补 `$` 而参数元数据自带 `$` ⇒ `$$a` —— 函数顶部剥前导 `$` | ✅ 已落地：门 H k_iterable 行 `RUN(2|2)` NOFACE；`($a)` 单 `$` 探针验证 |
| 5 | ~~`__NAMESPACE__` 硬编码空串~~ **✅ 已修复（#122b）** | `namespace KwhNsD5; echo strlen(__NAMESPACE__)` | 修复前 `7` vs `0` ⇒ 修复后同 `7` | 双根因：① **ir_generator.zig `.namespace` 臂**改读 `self.current_namespace orelse ""`（generateNamespaceStatement 本已维护该状态）；② **声明遍历的时序**——无 body 的 `namespace Foo;` 设完状态**立即恢复**且节点不进 `__main__` 语句流 ⇒ 生成期状态恒空 —— 修法 = 无 body 分支保持状态 + 节点按源顺序追加进 `__main__`（多段无括号 namespace 按序正确；大括号块的 prev_ns 恢复语义不变） | ✅ 已落地：d5a、`A\B`→3、`P\Q` + 命名空间内函数调用探针全绿 |
| 6 | ~~`函数名大小写不敏感解析缺失`~~ **✅ 已修复（#122c）**（d6a/d6b） | `$a=[1,2]; Unset($a[0]);` / `function Get(){} echo get();` | `1`/`11` vs 双双 `Fatal: undefined function` | 调用解析**精确匹配**：用户函数 `eql`（ir_generator.zig:6262）+ 内建表精确键（native_linker.zig:3906+/:4273）；PHP 函数名本不区分大小写 ⇒ 跨大小写调用双向全 Fatal（d6b/d6c 双向实测） | ✅ 已落地：`builtinInfo` 内建查名折小写重试（`Unset`→`unset`）+ `findUserFunctionCanonical` 大小写不敏感解析用户函数并按**规范声明名**发射符号 + unset 语言结构特判改 `eqlIgnoreCase`（d6a 元素删除写回）
| 7 | ~~`内建 go 条目遮蔽用户函数`~~ **✅ 已修复（#122c）**（d7a） | `function go(){ return 101; } echo go();` | `101` vs 空输出 | 生成码实读：用户函数已注册（`registerUserFunctionWithLocation("go", @"go", …)`）但调用仍发射 **`reg_0 = try runtime.php_go_builtin(…)`** ⇒ 内建表 `"go"` 条目（native_linker.zig:4273）+ go 构造符号 `@"go"`（:1676）在解析序上**先于**用户函数；控制臂 d7b `from()`（非内建）正常 ⇒ 撞名面 = `go` 一族 | ✅ 已落地：`.call` 发射决策改**用户函数优先**（`findUserFunctionCanonical` 命中 ⇒ 不走内建表）+ 运行期注册占位覆盖——`registerUserFunction`（go 协程族预注册）不再写 decl_locations，`registerUserFunctionWithLocation` 对无位置记录的占位放行用户覆盖（有记录 = 用户 vs 用户仍 Cannot redeclare） |

**修复优先级建议（终态，#122c 后）**：#1/#2/#4/#5/#6/#7 全部落地 ⇒ **唯余 #3（现网 `Get()` 式调用即命中，P1，需与 #7 同批设计解析序：用户函数优先 + 注册/查名两端折小写，常量/变量不折）** （P2，发射侧子轮定行后修复）。逐枚落地成本未实测（禁估算）；每枚动码前须按 §六 单独门控，验收面 = 门 D8 对应形转绿（现行 `defect_red=4`）且 GUARD_SAME 控制臂不动。**#122b 落地代次**：二进制 `f47263c25428ee14269ba4a985427c15`，parser.zig `e3987a36…`/4230 行、ir_generator.zig `bb9c00ed…`/9741 行；链 III 验收 = 影子 68/68 零漂移 + 门 H `face=1 noface=76 confounded=2`（k_and/k_var/m_namespace 转绿，余 k_goto/k_iterable）+ 门 I tree/bc 逐项不变 + 主回归 Pass 67/Skip 1。**#122c 落地代次**：二进制 `b416d3fbceed199b186676619043bcc5`；链 IV 验收 = 影子 68/68 零漂移 + 门 H **`face=0 noface=78 confounded=1 inverse_face=0 inverse_noface=21`**（k_unset/k_iterable/invf_go 全转绿）+ 门 I tree/bc 逐项不变 + 主回归 Pass 67/Skip 1。

---

## 9. 代次对齐登记（N1 收口，2026-10-08，老铁裁决 = 方案②「补登记等价证据」，不做整链复跑）

**背景**：交接审计（`docs/changes/2026-10-07/交接文档_2026-10-07_session9_R118-R120关键字穷举面闭环.md` §11 F-3）提出「当前二进制 `5beb1591018e6092ffc0ab0446344eee`（10-07 22:28:25 重建）未见登记，而六门 / 影子 / 主回归读数取自 20:46–21:16，早于 `ir_generator.zig` 22:27:16 的末次编辑」。本节为该缺口的等价取证，全部为 2026-10-08 实测。

### 9.1 先更正审计自己的措辞（被本节实测否证的部分）

门 TSV **自带代次头**：`# compiler_md5=` ＋ `# lexer_md5=` / `# keyword_lookup_md5=` / `# parser_md5=` / `# runtime_lib_template_md5=`。⇒ 注册代次（`b416d3fb`）**从来不是「无登记」**；真实缺口只是「当代次二进制未出现在任何注册头里」。F-3 的「未登记」据此收窄，交接文档 §11 已同步改写。

### 9.2 源码级等价（决定性证据）

| 文件 | 证据（实测） | 结论 |
|---|---|---|
| lexer / keyword_lookup / parser / runtime_lib_template | 门 TSV 注册头 md5 与现值全等：`e3dd4191a1c3dfdf816b5873b4c60e5f` / `ef70993a7caac6deb9b2e5a23bf7d143` / `e3987a361d1db45bc3eadefc7afa249e` / `5fdae1ab0cffde3eaba477a52a9713b4`；快照 ↔ 复跑头行逐字节相同 | 两代次源码同一 |
| native_linker | 文件 mtime 10-07 20:07:32，早于注册读数窗口（20:46–21:16） | 注册代次后未改动 |
| ir_generator | ① 现内容 = git blob `38442457ecbd`（9743 行，内容 md5 `96377ae7d33d52c6551a5daadefd886e`），该对象写入于 **10-07 20:48:54**；② 前一注册代次 #122b 的内容 = blob `eff0284c1c2c`（对象写于 19:07:03，内容 md5 `bb9c00ed…`，正是 §8 已登记的 `bb9c00ed…`/9741 行）；③ 两者 diff **恰为 §8 #6 那一枚 hunk**（`std.mem.eql(u8, func_name, "unset")` → `std.ascii.eqlIgnoreCase(...)` ＋ 2 行注释）＝归给 #122c 的改动；④ **21:16→22:31 窗口内对象库零写入** ⇒ 22:2x 的 goto 行为试验从未入库，22:27:16 的写回内容等于 20:48:54 已存在的内容 | 现内容 = 产出 `face=0` 那代（#122c / `b416d3fb`）的内容 |

⇒ 六个相关文件在两代次之间源码同一；`b416d3fb` 与 `5beb1591` 的 md5 差异**只能来自构建非确定性**（同源码不同产物）。此句为推断、由上述六项源码证据逼出，§9.3 的行为实测为独立复核，不作该推断的前提。构建非确定性本身**未做对照实验**（需覆盖正在验收的当前二进制 ⇒ 风险动作，未经老铁明示不做）。

### 9.3 行为级复核（当代次 `5beb1591` 实测，逐项等于注册值）

| 门 | 注册读数（快照 = `b416d3fb` 代） | 当代次复跑 | 行级 diff | 成本 |
|---|---|---|---|---|
| E | `same=19 diff=0 silent_empty=0 aot_fatal=0 compile_fail=0` | 全等 | 仅头行 + ELAPSED（66→68s） | 68 s |
| F | `same=8 diff=0 zero_instr=0 compile_fail=0` | 全等 | 仅头行 + ELAPSED（27→28s） | 28 s |
| G | `same=7 red_confirmed=0 guard_same=4 guard_red=0` | 全等 | 仅头行 + ELAPSED（23→24s） | 24 s |
| H2 | `over_accept=14 strict_same=1` | 全等 | 仅头行 + ELAPSED（52→53s） | 53 s |
| I | `aot_same=19 tree_same=7 tree_diff=12 bc_same=7 bc_diff=12 vm_only_red=12 aot_only_red=0` | 全等 | **仅头行**（compiler_md5） | 68 s |
| D8 | `defect_red=1 guard_same=13 compile_fail=0 bad_probe=0` | 全等 | 仅 ELAPSED（48→49s） | 49 s |
| H（子集 13 形） | `face=0 confounded=1(k_goto)` 各行 | 读数逐项一致 | **13/13 行逐字节相同** | 97 s（全量 721 s 未跑） |
| 影子（生成码 `main.zig` md5，子集 16 形） | new 侧注册 md5 | 读数逐项一致 | **16/16 SAME，diff=0，noref=0** | 213 s（全量 1502 s 未跑） |

- H 子集选形（覆盖 ir_generator 敏感面）：`k_goto k_namespace k_unset k_iterable m_namespace m_class k_function k_match k_include k_true k_null invf_go invm_struct`。
- 影子子集选形依据 = 语料对 §8 #5/#6 的命中实测（`namespace` 语料 1 形、`unset(` 语料 13 形、`goto`/`iterable`/`__NAMESPACE__` 语料 **0 形**）＋ 3 枚无敏感语法控制绿形（f174/f177/f179）。
- **合计实测 600 s ≈ 10 分钟**（方案①整链约 42 分钟）。

### 9.4 未复证面（明示，禁止当已验）

① 门 H 全量 79 形 / 200 臂 —— 只复证 13 形 26 臂；② 影子 68 语料 —— 只复证 16 形；③ 主回归 `run_regression.sh` —— 本代次未复跑（最近一次 = 10-07 21:16:02，`b416d3fb` 代，Pass 67 / Skip 1）；④ 构建非确定性无对照实验。

### 9.5 本节新增资产（📦 全部未提交）

- `fuzzy_scripts_720/tmp/c010_gen_align_subset_tmp.sh`（影子单侧子集，选形依据写于头注释）→ `c010_gen_align_subset_tmp.tsv`（md5 `e373f1b71e1436dae68054b08d4a9829`）
- `fuzzy_scripts_720/tmp/c010_genB_snapshot/`（注册代次九份 TSV 快照；逐份 md5：keyword_case `3ea26c92…`／mechanism `dacc656c…`／constant_case `6c7cc59b…`／kw_full_table `88b7f6b8…`／noface_tolerance `1af3a296…`／crossmode `8f6ecf40…`／indep_defects `0f1a4625…`／shadow `f3358264…`／gen_align `e373f1b7…`）
- `c010_kw_full_table_smoke_tmp.tsv`（H 子集，`SMOKE_ONLY=1`，**不覆盖**注册表）

### 9.6 第三层证据：老铁提交 `0652130` 使代次获得「提交即登记」锚点（2026-10-08 09:12:33 实测）

本节取证完成后，老铁将 §8 六枚修复（原暂存区 4 文件 `+114/−28`）以 `0652130`（消息 `11`）入库，HEAD 由 `b92f206` 前进，`git status --porcelain -- src/` 现 **0 项**。这把 §9.2 的「源码同一」从文件内容推断升级为**版本库锚点**：当代次二进制所编译的源码，就是 `0652130` 的内容。

| 文件（实测路径） | 工作树 md5 | `git show 0652130:<path>` md5 | 一致 |
|---|---|---|---|
| `src/compiler/lexer.zig`（543 行） | `e3dd4191…` | `e3dd4191…` | ✅ |
| `src/compiler/keyword_lookup.zig`（186 行） | `ef70993a…` | `ef70993a…` | ✅ |
| `src/compiler/parser.zig`（4230 行） | `e3987a36…` | `e3987a36…` | ✅ |
| `src/aot/runtime_lib_template.zig`（30857 行） | `5fdae1ab…` | `5fdae1ab…` | ✅ |
| `src/aot/native_linker.zig`（32823 行） | `3f05640c…` | `3f05640c…` | ✅ |
| `src/aot/ir_generator.zig`（9743 行） | `96377ae7…` | `96377ae7…` | ✅ |

⇒ 六枚 md5 与 §9.2 表（门 TSV 注册头 + git blob 取证）逐枚相同 ⇒ **`0652130` 的树 = 产出注册读数的那代源码**；后续任何会话可用 `git show 0652130:<path> | md5 -q` 复现该判定，无需再依赖 mtime。二进制仍为 `5beb1591…`（10-07 22:28:25），即「已提交源码 + 未重建产物」，§9.4 四项未复证面**不因本提交而消解**。

**结论**：N1 = ✅ 已收口（方案②；源码级 + 行为级双证，另有 `0652130` 提交锚点，残余未复证面见 §9.4）。本节零 `.zig` 改动、零 `.php` 删除、编译残留 0。

### 9.7 R-5 批代次登记（任务 #127，2026-10-09）—— §9.2 的等价取证对本批**不适用**

**三枚 AOT-only 旗标谱系（同一分叉口径，逐枚实测）**：

| 旗标 | 落地批 | 声明位置 | 置位位置 | 关闭时行为 |
|---|---|---|---|---|
| `Lexer.case_insensitive_keywords` | R-2（已入库 `0652130`） | `lexer.zig` | `initWithModeInsensitive` 内、**预取 curr/peek 之前** | 关键字查表大小写敏感＝历史 |
| `Parser.strict_alt_closers` | R-3（未提交） | `parser.zig:32` | `parser.zig:81`（构造后补设） | 五支 `end*` 闭合位＝历史软消耗 |
| `Parser.strict_switch_case_list` | **R-5（本批，未提交）** | `parser.zig:38` | `parser.zig:82`（构造后补设） | `switch` 臂表位意外 token＝历史整枚跳过 |

⇒ 两枚 Parser 旗标均在 `initWithModeInsensitive`（`:76–83`）内置位，而该构造器**只由 `src/main.zig` 与 `src/aot/multi_file_compiler.zig` 两枚 AOT 入口调用** ⇒ 解释器/字节码走 `init`/`initWithMode`（`:60–66`）⇒ 恒 `false`（承 §3.4.6 的 D-2 分叉裁决，门 I 已实测该分叉成立）。

**本批代次锚点（实测，非记忆）**：

| 资产 | md5 | 行数 |
|---|---|---|
| `zig-out/bin/php-interpreter` | `6939cd2e891f20aef590de2585b15681` | — |
| `src/compiler/parser.zig` | `1eab26c068b13b9f904d2f432464d852` | **4305** |
| `src/compiler/lexer.zig` | `e3dd4191a1c3dfdf816b5873b4c60e5f` | 543（**与 `0652130` 全等 ⇒ 本批零触碰**） |
| `src/compiler/keyword_lookup.zig` | `ef70993a7caac6deb9b2e5a23bf7d143` | 186（同上） |
| `git HEAD` = `f9432e2`（＝`0652130` 之后的文档/资产归档链） | `git show HEAD:src/compiler/parser.zig \| md5 -q` = `e3987a361d1db45bc3eadefc7afa249e`，4230 行 | — |

⇒ **算术自证**：`git diff --numstat src/compiler/parser.zig`（对 HEAD）= **81 插入 / 6 删除**，`4230 + 81 − 6 = 4305` ✅ ⇒ 未提交的工作树里同时含 **R-3 批（64/−6）与 R-5 批（+17/−0）**两批 ⇒ 提交时二者会落进同一 commit，**提交消息必须分别点名**，否则 R-3 的验收读数会被误挂到 R-5 名下（`git status --porcelain -- src/` 现仅 `M src/compiler/parser.zig` 一项）。

⇒ **§9.2 的「源码 md5 等价 ⇒ 免整链复跑」判定式在本批不成立**：本批改了 `parser.zig` 且改了**语义分支**（非纯注释，区别于任务 #74 的注释卫生批）⇒ 必须走全链（十门 + 主回归 + 影子）；影子门是本批**发射中性**的唯一实证（面 A 语料面 0 ⇒ 官方回归对立面 A 零暴露，见 §4）。
