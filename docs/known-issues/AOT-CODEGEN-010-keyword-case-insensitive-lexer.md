# AOT-CODEGEN-010 · PHP 关键字大小写不敏感支持缺失：非全小写拼写在 lexer 层坍成标识符 ⇒ 同一关键字按下游文法位置分裂出**五种不同结局**（静默空输出／运行致命／编译期解析失败／错臂无条件执行／偶然等值【非免疫】）；`keyword_lookup.zig` **87 枚表项穷举门**已实测 ⇒ 红面 **59 枚 / 79 形**

**问题 ID**: AOT-CODEGEN-010
**优先级**: **P0**（穷举面实测：静默空输出 **12 形** + 无消息错值 **7 形** 全程 rc=0 ⇒ 假绿；另有 **25 形**使**合法 PHP 语法在 AOT 编译失败**，按宪法 §七-8 前半句禁止以简化脚本绕过）
**性质**: 编译前端（`src/compiler/lexer.zig` + `src/compiler/keyword_lookup.zig`）⇒ **跨模式共享**：AOT 与字节码/解释器模式走同一 `lexIdentifier`；本轮按宪法 §五**只归因不修复**，且已实测两模式的结局同族（见 §2.2）
**状态**: **R-2 批 + §8 七枚缺陷中六枚已修复（2026-10-07），仅余 #3 goto（P2 子轮），📦 待提交**：R-2/R-2b/R-4 + 名位容忍支（已由老铁 `b92f206` 入库）＋ §8 #1/#2/#5（R123）＋ §8 #4/#6/#7（R124，调用解析序 + iterable + 消息渲染）全部落地并验收 —— 终态实测：门 H **face=0**（79 形全绿，原 59 红）+ **inverse_face=0**（反例组 21 形全绿，原 15 红）+ **confounded=1**（余 k_goto=#3）+ probe_compile_fail=0；门 E/F/G 全绿且守卫臂零越界；门 H2 `over_accept=14` 不变；门 I `aot_same=19` 且 tree/bc 读数逐项不变（D-2 分叉达成）；影子 68 语料 `main.zig` md5 **68/68 一致**；主回归 **Pass 67 / Skip 1** 保持。修复代二进制 `b416d3fbceed199b186676619043bcc5`
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
| `fuzzy_scripts_720/tmp/c010_noface_tolerance_gate_tmp.sh`（**永久侧门 H2 = 15 枚 NOFACE 的同位换瞎词判别门**，任务 #120 新立） | `8e11de20dd598f0875d166022f4c905c` | 99 |
| `fuzzy_scripts_720/tmp/c010_noface_tolerance_tmp.tsv`（侧门 H2 读数） | 门尾行 `C010H2_DONE shapes=15 over_accept=14 strict_same=1 aot_compile_fail=0 php_ok_aot_diff=0 repo_build_residue=0 SMOKE_ONLY=0` | `ELAPSED=54s`（= 3.6 s/形） |
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

**门资产与两轮读数（先修门、后引用）**
- 脚本 `fuzzy_scripts_720/tmp/c010_alt_syntax_gate_tmp.sh`（**v2** md5 `69806529f6bdf8feb2919dcac182db07`）→ `c010_alt_syntax_gate_tmp.tsv`（md5 `8b208dd0b9123c5f6bc8ee306cda5360`）；头行四枚代次戳 `compiler_md5=5beb1591… / lexer e3dd4191… / keyword_lookup ef70993a… / parser e3987a36…`，并带 `# gate_rev=v2`。
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

**修复建议（本会话未动一行源码，按宪法 §五/§六 待裁决）**

| 优先级 | 影响面 | 落地成本 |
|---|---|---|
| **P1** 把 `:1515-1517`（`endif`）与 `:3563-3565`（`endswitch`）的软消耗改为**硬 `eat`**，与 `:1581`/`:1672`/`:1833` 对齐 ⇒ 一次消 5 枚 OVER_ACCEPT 中的 2 枚根因面并让另 3 枚报错点后移到明确位置 | 仅 parser 错误路径；正例面（16 形 + 真实语料 3 枚）零影响，因它们本就走完整闭合；**风险 = 现网"缺闭合"脚本从静默错输出变编译期报错**（即 §七-1 意义上更正确） | **未实测**；复测 = 门 J 77s（预期 `over_accept 5→0`、`same=16` 不变、`both_reject 2→7`）+ 主回归 68 语料（语料面 0 ⇒ 预期零扰动） |
| **P1** `:1594` 体扫描补「异种 `end*` 即终止并报 unexpected」 | 消 `n_mismatch_end`/`n_double_endif`/`n_endif_alone` 三枚的直接入口 | **未实测**；同上复测档 |
| **P2** `tagToExpected:220-235` 补 `.k_*` 臂（至少 5 枚 `end*`），使消息与 PHP 对齐（`expecting "endwhile"`） | 纯错误消息面，语义零影响 | **未实测**；秒级门 J 的 `aot_log=` 列即验收位（v2 门已把该列做成可断言字段） |
| **P2** 维持现状 + 只把门 J 当**守卫门**（读数不得变化） | 零风险，但 5 枚宽容面长期存在 | 77s/轮 |

---

## 4. 语料面与风险

| 维度 | 结论 |
|---|---|
| 68 语料面（**穷举实测**） | `grep -onE '\b(Echo\|ECHO\|Print\|PRINT\|If\|IF\|Else\|ELSE\|Elseif\|Return\|RETURN\|Function\|FUNCTION\|Class\|CLASS\|New\|NEW\|ForEach\|FOREACH\|True\|False\|Null)\b' fuzzy_scripts_720/pass/*.php` ⇒ 命中 10 处（f016:196 `True`、f038:144 `New`、f072:180 `Function`、f113:192 `New`、f151:82 `Return`、f152:96/120 `Function`、f179:170 `If`/181 `Else`/295 `Function`/268 `Print`）⇒ **逐处回文核对：全部位于字符串字面量内**（如 `echo "New total: "`、`$this->output .= "If\n"`）⇒ **关键字位的混合大小写命中 = 0 处** |
| 判据 3/4 应用 | 「扫描器 0 命中 ≠ 语料 0 命中」在本单成立：扫描器有 10 处命中但**语料内真实触发面为 0** ⇒ 冻结基线对本面**零保护力**；同时该面**机制可达**（任何混合大小写关键字书写即命中），语料 0 只说明绿语料恰好全用小写 |
| **替代语法家族语料面**（2026-10-08，`token_get_all` 分词器实测，见 §3.6） | 与关键字大小写**无关**但共用同一 `lexer/parser` 前端 ⇒ 一并登记：冻结基线 `pass/` 68 文件 + `fail_runtime/` 77 + `fail_compile/` 12 的**替代语法开口头与关闭标记均为 0**（32 处粗筛命中全在字符串/注释内）⇒ 正例面（已支持）与负例面（5 形过度接受）**都不受官方回归保护**；同判据 4「机制完全可达」 |
| R-2b 面语料穷举（任务 #119 实测） | `grep -onE 'constant\(' fuzzy_scripts_720/pass/*.php` ⇒ **0 命中**；`grep -onE '\bdefined\('` ⇒ **0 命中** ⇒ 冻结基线对常量表拼写面**零暴露**；同判据 3/4：语料 0 ≠ 机制 0，任何用 `constant("true")` 风格动态查名的现网脚本即命中 |
| 静默性 | **本单最危险处**：三形空输出 + 一形错臂双输出 + 一形错值全为 rc=0、无 warning、无 fatal ⇒ 若用户脚本用 `Echo`/`Print`/`IF`/`RETURN` 风格书写，官方回归「输出比对」会抓到（语料内无此形 ⇒ 现网脚本才会踩）；反之「整段静默不输出」在只看 exit 码的门里会被判绿 ⇒ 侧门 E 的 `silent_empty` 计数器专门盯这一类 |
| 修复的破坏面 | 前端 lexer 改动 ⇒ **触发冻结基线漂移风险**（`main.zig` 生成码取决于 token 序列）；但语料关键字位混合大小写 0 处 ⇒ 只要改动只让「原先查不中的拼写」命中，理论上发射中性，**该中性未影子实测**。风险点：PHP 的标识符大小写规则不统一（类/函数名不敏感、变量敏感），若在 lexer 层无条件归一化大小写会**误伤变量名/类名原文**，必须先定「只在关键字位查表归一、token 文本仍交原文」的形态 |
| **门 H/H2 派生独立缺陷的语料面**（任务 #120 穷举实测，`fuzzy_scripts_720/pass/*.php` 68 文件） | 逐族回文核对 ⇒ **两类**：① **有面且已绿** = `callable` 类型位 **59 处**（f047×16、f152×14、f042×6、f090×5、f151×3、f171×2、f163×2、其余各 1）⇒ 小写 `callable` 在 AOT **可用**（修模板后侧门 H 判为 `FACE`：只有混合拼写红）；② **语料面 0** = `and`/`or`/`xor` **真运算符位** 0 处（35 处命中全在字符串字面量/注释内；另 14 处非字符串命中**全部是用户自定义方法名** `->and()`/`->or()`/`::xor()` ⇒ 恰好落在「标识符名位容忍」支上 ⇒ **语料绿直接依赖该容忍支**）、`var` 属性声明 0、`goto` 0、`iterable` 0、`__NAMESPACE__` 0 ⇒ 判据 3/4 同 §4 上表：这些族的红面对冻结基线**零暴露**，但机制可达（现网脚本用即命中） |
| **标识符名位容忍面**（任务 #120 只读实文 + 实测计数） | `parser.zig:3761 isKeywordIdentifierTag` **实测只列 74 枚 `.k_*` tag**（**本行旧措辞「全部 87 枚」经 `:3761`–`:3840` 逐枚计数为错，已更正**）。表内 80 枚小写 `k_*` 中**被排除的 6 枚** = `.k_endfor` `.k_endforeach` `.k_endif` `.k_endswitch` `.k_endwhile` `.k_struct`；魔术常量 7 枚为另一套 tag，不在此清单。容忍支经 `:3843 eatKeywordAsIdentifier` 在 **8 处**名位调用（`:762`、`:946`、`:1263`、`:2181`、`:2465`、`:2524`、`:2563`、`:2869`）⇒ 语料实测命中：`->(get\|set\|lock\|from)` **45 处 / 8 文件**（f037×15、f016×8、f056×7、f173×7、f178×4、f010×2、f057×1、f040×1）、`public function (get\|set\|lock)(…)` 声明 **24 行 / 7 文件** ⇒ **全部落在名位 ⇒ 语料绿与此容忍支直接相关**。⇒ 结论（**已由门 H 反例组 21 形实测坐实，不再是推断**）：被抢注成 token 在**有容忍支的名位**不致害（`invm_*` 六枚绿），致害面在**无容忍支的名位** = 顶层函数名 `:1405` 与类名 `:1319-1321`（`invf_*`/`invd_*` 各 7/7 红）+ **清单漏项名位**（`invm_struct` 红，因 `.k_struct` 不在 74 枚内）⇒ 详见 §3.4.2 |

---

## 5. 修复路线（优先级 / 影响面 / 落地成本 —— 成本列为「实测」或「未实测」，禁列估算）

> **落地状态（2026-10-07）**：**R-2 / R-2b / R-4 已落地并验收**（形态与实测读数见 §3.4.6；R-2 与名位补洞同批 = D-1 甲裁决，分叉旗标门控 = D-2 裁决）；**R-3（金丝雀）仍未启动**。落地实测成本：验收链 II = 影子 ~2400s + 六门 822s + 主回归 ~834s；源码改动 8 文件 +268/−78 行（git diff HEAD 实测）。

| 路线 | 内容 | 优先级 | 影响面 | 落地成本 |
|---|---|---|---|---|
| **R-1** | ~~归因轮（前置）~~ **已闭环（任务 #119，永久侧门 F）**：五类下游断点逐类到行，见 §3.1 | P0 前置 | 只读，零源码改动 | **实测 `ELAPSED=30s` / 8 形 = 3.75 s/形**（含生成码结构实读一枚额外编译；另侧门 E 19 形 `60s`） |
| **R-2** | 关键字查找改大小写不敏感：`keyword_lookup.zig` 增加忽略大小写的查表路径（`lookup` 侧一次性归一，或 `eqlIgnoreCase` 线性/两级分派），`lexIdentifier` 仍交**原始 token 文本**（勿把归一化后的文本喂给 identifier 语义）。**形态先例（任务 #120 只读实文）**：`parser.zig:3857` 名位标识符名取自 `self.lexer.buffer[name_tok.loc.start..name_tok.loc.end]`（**原文切片**，不经任何大小写归一）⇒ 「查表归一 + 文本交原文」的分工在前端里**已存在**，R-2 只需照此形把 `keyword_lookup` 的查表侧改敏感、名位取文本侧保持原样，非新发明 | P0（本单收口） | **验收面已实测穷举（任务 #120，门 H）= 59 形**：34 FACE（含 2 枚仅警告噪声 ⇒ 语义红 32）+ 25 探针编译失败 ⇒ 语义红面合计 **57 形**；另有 15 枚「宽容绿」须按 §3.4.5 判据 2 **比对生成码**才算收口。编译前端全量 token 流 ⇒ **可能触发冻结基线漂移**；须先影子实测 68 语料 `main.zig` md5。**新增实测约束（本代次更正，旧措辞「名位对 R-2 中性」已作废）**：`isKeywordIdentifierTag`（`:3761`）**实测只列 74 枚** `.k_*` tag，且顶层函数名 `:1405`／类名 `:1319-1321` **根本没有**容忍支 ⇒ 名位**并非**对 R-2 中性。R-2 落地后 `Echo` 类混合拼写将改走 `k_echo` 支；**同时** `function Get()`／`class With()` 一类**今日因查表落空而侥幸绿**的混合大小写外族词会**首次**命中 `.k_get`/`.k_with` ⇒ 在这两处硬名位**新增编译失败面**（今日实测该面 0 红，见 §3.4.2 补充探针 1）⇒ **R-2 必须与「两处名位补 `eatKeywordAsIdentifier` 兜底 + 继续 intern 原文切片」同批落地**，并一并核对清单漏掉的 6 枚 tag（`.k_struct` 已实测在方法名位致红）。另需核对**魔术常量组**（表键 `__DIR__` 等为大写、表内 7/87 枚为此规范，归一方向取反反而**丢**命中 ⇒ 门 H 的 `m_*` 六形为其判据） | **未实测**（落地后必须跑的门与**实测单价**：门 E `60s` + 门 F `30s` + 门 G `26s` + 门 H `595s` + 门 H2 `54s` + 门 I `57s` = **822s**，再加 68 语料主回归 `run_regression.sh` 与影子 md5 对照 ⇒ 验收门合计约 **14 分钟**（不含主回归）；H2/I 为**守卫门**，预期读数不变（§3.5、§6）） |
| **R-2b** | **常量表拼写面（与 lexer 缺陷无关的第二张独立面孔，任务 #119 实测新立 ⇒ 永久侧门 G）**：运行期常量表按**大写单拼写**建键（`runtime_lib_template.zig:7614/:7615/:7637`）⇒ **动态查名入口**实测红：`constant("true")` PHP `a=true` vs AOT `Fatal: Undefined constant "true"`；`constant("false")`/`constant("Null")` 同红。覆盖面实测收窄到**仅 `true`/`false`/`null` 三枚**：`constant("php_int_max")` 在 PHP 8.5.8 **亦** Fatal 且 AOT 侧逐字节等值 ⇒ 非关键字常量本就该敏感；`define("GgC1",7)` 后 `constant("GgC1")` 两侧同 `7`、`constant("ggc2")` 两侧同 Fatal ⇒ 用户常量侧 AOT 与 PHP **已等值**，扩面即为回归。⇒ **R-2 只改 lexer 对该面零收敛**（探针源码内无任何大写关键字拼写） | P0（本单第二张面孔） | 生成码 `getGlobalVar` 的 `runtime.constants.get(name)` 查名路径（`main.zig:1066-1070`）**或**常量表建键侧；二者取其一即收口，需先定形态，且**限定只放开三枚关键字常量名** | **取证已固化为永久侧门 G**（7 形实测 `ELAPSED=26s` = **3.7 s/形**，逐形读数见 §3.3；其中一枚因 `cd` 到仓库根以外目录执行而报 `executable generation failed: FileNotFound` 且无产物 ⇒ **复测必须在仓库根**）；落地成本未实测 |
| **R-3** | 静默面兜底金丝雀：发射期断言「语句位置出现 `t_string` 且其原文忽略大小写等于关键字表条目 ⇒ 立即报错」，把「静默空输出」在任何修复前后都转成**编译期可见错误** | P1（防回归） | 只加断言支路，不改语义；对合法脚本零影响。**覆盖面实测收窄**：§3.1 D 类与 E 类**均非零指令**（`m_else_upper` 的 `instr=9 echo=2` 与控制臂**逐位相同**；`m_true_upper` 为 `instr=10`）⇒ 零指令金丝雀**只能抓 A 类**，D/E 类需另行判据 | **未实测**（可参考 CODEGEN-005/006 系列发射期金丝雀先例） |
| **R-4** | `lexIdentifier:390/:394` 的 `len <= 15` 硬编码上限改为按表内最长键计算（消除「更长关键字静默不查」的潜在面） | P2 | **本代次实测更正**：87 枚键最长为 `__NAMESPACE__`（13 字符）⇒ 距上限**仅剩 2 字符余量**（旧措辞「最长 9 字符 ⇒ 现在无面」已按 `grep -oE` 实测更正）。现在仍无面，但「未来静默失效」的距离比旧估计近得多；且 **R-2 若改为「忽略大小写两级表 / 折叠副本表」，表结构一旦重排就必须同步把上限改为按表计算**，否则新增条目可能悄悄越界 ⇒ 与 R-2 **同批**做，零额外成本 | **未实测**；若与 R-2 同批则零额外成本 |

**门控声明**：R-1 归因轮属「只读取证」，已在 `继续推进` 授权范围内完成；**R-2 / R-2b / R-3 / R-4 任一落地前仍需老铁点头**（宪法 §六：编译前端语义改动 + 可能损失/改变发射形态；§五：跨模式（解释器/字节码）同面**是否一并修**亦需明示）。

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

# 永久侧门 H2（15 枚 NOFACE 成因判别 = 同位换瞎词，实测 54s）
timeout 300 bash fuzzy_scripts_720/tmp/c010_noface_tolerance_gate_tmp.sh
# 当前代次预期：C010H2_DONE shapes=15 over_accept=14 strict_same=1 aot_compile_fail=0 php_ok_aot_diff=0，ELAPSED=54s（= 3.6 s/形）
# 判读：**本门不比谁对，只比「AOT 是否接受 PHP 不接受的」** ⇒ over_accept 计数即「宽容位」清单
# 修复后预期：R-2 落地后 `Zkwhq` 仍**不是**关键字 ⇒ over_accept **应保持 14 不变**（本门不是修复验收门，是成因门）
#   ⇒ 若 over_accept 归零，说明改动把「任意标识符」也吞进了关键字支（越界），须回退
#   ⇒ 唯一零判别形 `n_never`（PHP 对未知返回类型在 throw 形不报错）永久保持 strict_same

# 永久侧门 I（跨模式 AOT/tree/bytecode，门 E 同批 19 形，实测 57s）
timeout 480 bash fuzzy_scripts_720/tmp/c010_crossmode_gate_tmp.sh
# 当前代次预期：C010I_DONE shapes=19 tree_same=7 tree_diff=12 bc_same=7 bc_diff=12 aot_same=8 aot_diff=8 aot_compile_fail=3 both_red=11 vm_only_red=1 aot_only_red=0，ELAPSED=57s
# 修复后预期（R-2 天然三模式同修 ⇒ 见 §2.2 结论 1）：tree_same=19 bc_same=19 aot_same=19，三种 _diff 与 aot_compile_fail 全 0
#   **七枚 `*_ctl` 控制臂在三模式下必须始终 SAME**；`norm()` 已含「从 `=== PHP Interpreter Performance Statistics ===` 起整段删除」，
#   若某日全部 VM 臂恒 DIFF ⇒ 是 VM 统计段标题变了（门坏），不是编译器回归

# 永久侧门 J（替代语法正/负例 23 形，v2 实测 77s = 3.3 s/形；必须在仓库根执行）
timeout 300 bash fuzzy_scripts_720/tmp/c010_alt_syntax_gate_tmp.sh
# 注册读数（v2，脚本 md5 69806529…）：C010J_DONE shapes=23 same=16 diff=0 over_accept=5 both_reject=2 aot_only_red=0 run_red=0 both_err_diff=0 repo_build_residue=0，ELAPSED=77s
# 跨 run 复证（2026-10-08 第二轮，同脚本同代次）：汇总列逐项等值，表 md5 6d4dc390… → 把 ELAPSED 归一回 77s 后 = 登记值 8b208dd0… ⇒ 除耗时行外逐字节全等
#   ★ 本 TSV 与门脚本**均未入库**（`git show 0652130:` 取不到）⇒ 复跑前须以脚本 md5 69806529… 自证门的代次，勿凭文件存在性判断
# 判读：same=16 ⇒ 正例面（已支持）；over_accept=5 ⇒ 宽容面（PHP 拒而 AOT 收）；both_reject=2 ⇒ 硬 eat 位与 PHP 同拒；
#   ★ aot_only_red 与 run_red **必须恒为 0**：任一转正即「替代语法从可用变不可用」的真回归（本门唯一的硬守卫列）
#   ★ diff 判据是「AOT 与 PHP 输出逐字节等值」⇒ 与 §3.5 的 H2 判读口径同源：本门**不比谁语义更对**，只比接受/拒绝边界
# 修复后预期（若裁决把 :1515/:3563 软消耗改硬 eat + :1594 补异种 end 终止）：over_accept 5→0、both_reject 2→7、same=16 不变、aot_only_red=0
# 修门提醒：**v1（脚本 4009de13…／表 a8afda22…）的数据列禁止引用**（`tr '\n' '|'` 撑破列契约 ⇒ n_* 行 NF=9），
#   其四列 key（shape/php_rc/aot_rc/verdict）仍可与 v2 逐行对照 ⇒ 已实证 23/23 全等，修门未扰动判据
# 语料面复扫（分词器口径，判据 3/4；pass 目录实测输出 3 行：root/php_files、close 计数、alt 开口头 + 花括号头计数）：
timeout 30 /opt/homebrew/bin/php fuzzy_scripts_720/tmp/c010j_alt_corpus_scan_tmp.php fuzzy_scripts_720/pass
# 预期：close_marker_tokens_at_syntax_position=0 / alt_syntax_headers=0 ⇒ 冻结基线对本面零保护；
#   一旦两值同时 >0 ⇒ 语料已新增替代语法用例，本门从「守卫门」升级为「验收门」
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

**复测纪律（实测仅门 H / H2 / I 含 `ONLY=` 冒烟通道；门 E/F/G 经 `grep -c ONLY` 实测**无**该通道）**：`ONLY=` 冒烟通道写入的是**独立的** `*_smoke_tmp.tsv`，其总数行带 `SMOKE_ONLY=1` ⇒ **禁止当作全量读数引用、用完必须删除**（门 I 首跑的「smoke 里装了全量」、门 H 反例组的 3 形冒烟、以及归因轮里曾用临时脚本产生的假 `zero_instr=8` 三坑同源；注册读数一律取自无 `ONLY` 的全量跑）。

---

## 7. 遗留 / 待裁决 / 流程项

1. ~~八枚红形的下游失败点未逐形归因~~ **已由 R-1 闭环（任务 #119）**：五类断点逐类到行（§3.1），A 类零指令 / B 类差一对括号 / C 类语句层臂表缺项 / D 类落点在守卫之外 / E 类两处缺陷互抵消 ⇒ 「R-2 一枚改动可能只消部分面」这一疑虑已被**实测收窄**：A/B/C/D 四类**同源于 lexer 一枚根**（D 类只是文法位不同 ⇒ 落在守卫外），故 R-2 可一次消四类；**唯一消不掉的是 E 类的第二张面孔**（常量表动态查名，源码内无大写关键字 ⇒ 必须并批 R-2b，见 §3.3）。
2. ~~混合大小写关键字族的覆盖面未穷举~~ **已由永久侧门 H 闭环（任务 #120）**：按 `keyword_lookup.zig` **87 枚表项**自动生成 79 形（87 − 7 枚外族词走反例组 − 1 枚 `yield` 属宪法 §七-1 排除项），一形一文件、双臂只差拼写，实测 `ELAPSED=595s`（**100 形含 21 形反例组 = 6.0 s/形**）⇒ 覆盖面从 E 的 19 形扩至 79 形、红面从 11 枚扩至 **59 枚**。逐类读数与三分文法位见 §3.4.1，过度识别名位矩阵见 §3.4.2。
3. **`len <= 15` 硬编码上限**（`lexer.zig:390`/`:394`）：**实测最长键 13 字符（`__NAMESPACE__`）⇒ 仅剩 2 字符余量**，非「远在安全区」。属宪法 §四-3「禁止硬编码」的存量违反，登记待与 R-2 并批（R-4）。
4. ~~跨模式是否一并修（证据仅 4 形定性）~~ **已由永久侧门 I 量化（任务 #120，19 形 × AOT/tree/bytecode）**：实测 `aot_only_red=0`、`both_red=11`、`vm_only_red=1`（见 §2.2）⇒ **不存在「只修 AOT 即可关掉的形」**，且本单根因在三模式共享的编译前端 ⇒ 需老铁裁决的问题已收窄为「**是否接受 R-2 天然三模式同修**」（宪法 §五 的形式要求由实测替代：无法只动 AOT 一侧，除非分叉前端）。
5. **`--compile` 解析失败仍返回 0 且不产出二进制**：本面使官方门若只看 exit 码会把「编译失败」读成「运行成功但无输出」。属**测试流程**问题而非编译器语义，建议单列（与 RUNTIME-002 §7-4 的 skip-before-compile 流程项同族，可并批讨论）。
6. ~~`TRUE`/`FALSE`/`NULL` 为何免疫~~ **已闭环并改判为「非免疫」（任务 #119）**：成因 = 大写失配 → `.variable "TRUE"` → `getGlobalVar("TRUE")` → 命中运行期**大写单拼写键**内置常量表（`runtime_lib_template.zig:7614/:7615/:7637`）⇒ 与 lexer 缺陷**互抵消**才呈 SAME。⇒ 原设想「用它当 R-2 的实现先例」**不成立**（它不是大小写不敏感通道，前端仍是零先例）；反之发现该表自身是**第二处独立缺陷**（§3.3 / R-2b）。
7. **C 类无生成码侧读数**：侧门 F 的 8 形全为可编译形 ⇒ C 类的断点（`parser.zig:496 else =>` 后接 `:2747 parseUnary` 无臂）来自「侧门 E 的 `compile.log` 错误文本 + parser 实文核对」，**未取 AST 侧行级读数** ⇒ 若 R-2 落地后 C 类三形仍红，需另开 AST 探针轮。
8. **D 类 `reg_5` 跳号属推断**：实测事实 = 生成码内 `reg_4`（then 串）之后直接是 `reg_6`（else 串），`reg_5` 全文 0 次出现；「`ELSE` 语句占用了 IR 寄存器号却未发射任何指令」是对该跳号的**推测解释**，未经 IR 侧取证 ⇒ 禁止在 R-2 落地评审中当证据引用。
9. **侧门 F / G / H / H2 / I 五张为本轮新建资产**：尚未纳入官方十二腿门链，且与本轮全部工单文档同样**未提交**（待老铁「提交」指令）；五门总数已按「先修门、后引用」口径只登记修正后读数（H 的两轮修门见 §7-11）。**2026-10-08 追加第六张 = 侧门 J（§3.6，替代语法正/负例）**，处置口径相同：未入库、未纳官方门链、v1→v2 两轮读数按「先修门后引用」登记 ⇒ **D-7 的问询范围现为十门**。
10. **`parser.zig:3756-3759 isKeywordUsableAsIdentifier` 是恒返回 `false` 的死桩**（任务 #120 只读发现）：文档注释写「any keyword that can be used as method/property name after -> or ::」，但函数体 `return false;`，且**全树零调用点**（真实能力在同文件 `:3761 isKeywordIdentifierTag` + `:3843 eatKeywordAsIdentifier`，8 处名位调用）。⇒ 属宪法 §四-2「禁止打桩/stub 跳过真实逻辑」的**存量**违反，且对后续读码者是**误导源**（会以为名位不容忍关键字，而语料 45 处 `->get/->set/->lock` 全靠该容忍支才绿）。⇒ **删除或改名均需 §六 点头（涉及删除代码）**，本轮只登记；与 §5 的 R-2/R-4 不同批（不属大小写面孔，动它=纯注释/死码卫生）。
11. **侧门 H（87 枚表项穷举门）已建并两轮修门后闭环**（任务 #120）：`fuzzy_scripts_720/tmp/c010_kw_full_table_gate_tmp.sh` ⇒ `c010_kw_full_table_tmp.tsv`。逐形双臂（同模板只差拼写）+ 过度识别反例组。**两轮修门均为「先修门、后引用」**：① `k_callable` 坏探针（Go 风格 `fn(): int {}` 被 PHP 自己拒）⇒ 补 `php -l` 预检 + `BAD_PROBE_*` 两类，读数 `face 58→59`、`confounded 6→5`、`bad_probe=0`；② 反例组旧版 7 形各用**不同名位** ⇒ 「`get`/`set` 绿」实为方法名位的功劳而非该词无害（**已由 3 形冒烟实测证实同一词的函数名位/类名位红、方法名位绿**）⇒ 形集改为 **7 词 × 3 名位 = 21**。两版首跑读数均**禁止引用**，注册读数取自最终全量跑（§3.4）：`C010H_DONE shapes=79 arms=200 … inverse_shapes=21 inverse_face=15 inverse_noface=6 inverse_confounded=0 repo_build_residue=0 SMOKE_ONLY=0` / `ELAPSED=595s`，且主群 79 行跨 run `diff_bytes=0` ⇒ 修门未扰动主群。
12. **五枚与大小写无关的默认档独立缺陷是否立单（待老铁裁决）**：`k_and`（括号操作数组内 `and` 求值错、静默 rc=0）、`k_var`（`var` 属性声明编译失败）、`k_goto`（`goto` 形使尾部整体消失）、`k_iterable`（`iterable` 拒绝数组 + 消息内 `$$a` 双 `$` 渲染）、`m_namespace`（`__NAMESPACE__` 在 `namespace` 声明后取空串）。⇒ 逐枚**不属于**本单 lexer 根，R-2 不消（§3.4.3）⇒ 按宪法 §五「不扩散」原则本轮只登记；若要修需另立工单（`var`/`goto`/`and` 三枚属解析与求值面，`$$a` 属消息渲染面）。
13. **AOT 重复警告行（新观察，未归因）**：同一未定义变量 AOT **连打两行** —— `Warning:  Undefined variable True`（双空格）与 `Warning: Undefined variable True`（单空格），PHP 只打一行 `PHP Warning: …`。出现在门 H 全部含 `Undefined variable` 的红面行，小写臂不出现 ⇒ 与本单根因无关，疑为警告发射点重复（登记待归因，优先级 P2；因其污染等值判据，**任何以「输出逐字节等值」为准的门都会因此多算红**）。
14. **返回类型声明校验面无工单归属**：§3.5 三枚类型形（`void`/`mixed`/`object`）证明 AOT 对**未知/非规范拼写的返回类型名不校验**（PHP 侧 Fatal）。⇒ ①「AOT 对**已知**返回类型（`: int` 等）是否校验」**本门未测**；② 已核对 `AOT-TYPE-001` = PHI 节点类型混接、状态 CLOSED ⇒ **不覆盖**本面；③ 近邻仅 `AOT-RUNTIME-002` G4 的 typed 槽六面（静态属性侧）。⇒ 若要定面需**另立门/另立单**，禁止由本表外推。另 `n_never` 为**永久零判别力**形（PHP 对只 `throw` 的 `: never` 体不报错 ⇒ 无对照可选），登记于此而非门缺陷。
15. ~~替代语法（`if:`…`endif;` / `switch:`…`endswitch;`）是否真被支持仍不可判~~ **已由永久侧门 J 闭环（2026-10-08，任务 #123 建门并实测；详见 §3.6）**：正/负例 23 形实测 `shapes=23 same=16 diff=0 over_accept=5 both_reject=2 aot_only_red=0 run_red=0 ELAPSED=77s` ⇒ **判为「真支持」**（16 枚正例逐字节等值 + 旧语料 `fuzzy_scripts/test_006/007/008` 三枚真实脚本内含 5 枚替代语法构造亦 3/3 等值），五支 `is_alternative` 支路产出标准 AST 节点 ⇒ 发射侧语法无关。**代价是新立一张面孔**：5 形 **OVER_ACCEPT**（缺 `endif;`、缺 `endswitch;`、异种 `endwhile`、顶层裸 `endif;`、双 `endif;` ⇒ PHP rc=255 而 AOT rc=0 且静默），分界实测为**关闭标记消耗软硬不对称**（`if :1515-1517`／`switch :3563-3565` 软，`while :1581`／`foreach :1672`／`for :1833` 硬）+ `:1594` 体扫描只认同种 end 标记 + `:3299-3305` 旗标容忍支把多余 `end*` 降级成变量语句。语料面按分词器实测为 **0**（`pass/`68、`fail_runtime/`77、`fail_compile/`12 的开口头与关闭标记全 0；32 处粗筛命中全在字符串/注释内）⇒ 判据 3/4：正例与负例**都不受冻结基线保护**，但机制完全可达。⇒ 修复（软改硬 + 体扫描补终止）**属新决策面，未落地**，建议表见 §3.6 末，待老铁裁决。
15b. **门 J 自身两轮读数代次（先修门、后引用）**：v1（脚本 `4009de13…`／表 `a8afda22…`）有两个门缺陷 —— `tr '\n' '|'` 与列分隔符冲突致报错行 NF=9 撑破 7 列契约、compile_fail 支未记录 AOT 原文 ⇒ **v1 数据列禁止引用**；v2（脚本 `69806529…`／表 `8b208dd0…`）修复并复跑，`(shape, php_rc, aot_rc, verdict)` 四列与 v1 **逐行全等 23/23** ⇒ 修门未扰动判据。附带发现：`tagToExpected:220-235` 无任何 `.k_*` 臂（兜底 `else => "token"`）⇒ 硬 `eat` 的期望词名不如 PHP 精确，P2 消息面。
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
