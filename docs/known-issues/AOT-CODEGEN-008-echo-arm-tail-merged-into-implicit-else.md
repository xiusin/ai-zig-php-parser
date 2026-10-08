# AOT-CODEGEN-008 · 臂尾最后一条语句为 `echo` 时，无 `else` 的 if/elseif 链把「链后语句」并入隐式 else 臂：静默截断 + 函数隐式返回 null + 循环 latch 丢失（默认档即触发，rc=0）

**状态**: OPEN（2026-10-07 立项，任务 #114 的回收覆盖过程中挖出；门 `c008_chain_tail_gate_tmp.sh` 实测 `same=10 diff=8 compile_fail=0 elapsed=37s`；**缺陷本体未修，路线待点头**）
**性质**: AOT **发射侧**缺陷（AST-direct 发射的 if/elseif 链 merge 归属错误）⇒ 修复需改 `src/aot/native_linker.zig`（664KB 超大文件，宪法 §一-2）⇒ **属门控改动，未经点头禁止动手**
**触发档**: **默认档**（`--compile`，无 `--optimize`）即触发 ⇒ 与 CODEGEN-007（仅非默认档）不同，本形是当前冻结基线代次的活缺陷
**语料面 = 0（但机制可达）**: 68 枚语料在代次 `1f15e4ce…` 实测 Pass 67 / Skip 1，本形零命中；含 `elseif` 且全文无 `else` 关键字的仅 4 枚（`f032`/`f038`/`f087`/`f124`），其臂尾语句均为**数组追加/赋值**而非 `echo`（`f032:61-64` 实测为控制臂同构）⇒ 按判据 4，「语料 0」不等于「无缺陷」，最小复现仅 5 行
**代次锚点**: `zig-out/bin/php-interpreter` md5 `1f15e4ce9b5c9cdaaef7cabf5efb9c76`；`src/aot/runtime_lib_template.zig`（本轮实测 30810 行发射副本 `runtime_lib.zig`）未改；`fuzzy_scripts_720/pass/f004_oop_deep_inheritance_magic.php` 未改（PHP 源文件保护铁律）

---

## 1. 共因（四条，全部实测二分，非推断）

| # | 条件 | 正例（红） | 反例（控制臂，绿） |
|---|---|---|---|
| 1 | 链**没有** `else` 臂 | P1 `if/elseif` | **C1** 同体补 `else` ⇒ 三形全 SAME |
| 2 | 某个可命中臂的**最后一条语句是 `echo`** | P1/P2/P3/P4 臂体仅 echo | **C3** 臂内 echo 后多一条数组追加 ⇒ SAME；**C4** 臂尾改为无返回值用户函数调用 ⇒ SAME（排除「任何被忽略结果语句」这一更宽假设） |
| 3 | 链后同一块内还有语句 | P1 链后 `echo AFTER/END`；P2/P3 链后 `return` | **C2** 臂尾为数组追加，链后 `return` ⇒ SAME（语料 `f032` 即此形，故语料不可见） |
| 4 | 命中臂（走任一臂尾 echo 的路径） | P1 `arg=a/b`、P2 `a/b`、P4 `a` | 零臂命中走隐式 else 时链后语句**反而正常**（P1/P2/P4 的 `arg=z` ⇒ SAME）⇒ 直接证明链后语句已发射，只是**归属块错** |

**作用域无关**：顶层 `__main__`（P1）、自由函数（P2/P3）、方法（语料 `f032` 同构）、循环体内（P4）全部命中。

---

## 2. 症状（门实测原始读数，`fuzzy_scripts_720/tmp/c008_chain_tail_gate_tmp.tsv`）

| 形 | 结构 | arg | AOT 输出 | PHP 真值 | 判定 |
|---|---|---|---|---|---|
| **P1** `c008_p1_top_echo_arm_tmp.php`（5 行最小复现） | 顶层 `if/elseif`（无 else）臂尾 echo + 链后 2 条 echo | `a` | `1` | `1/AFTER/END` | **DIFF，rc=0** |
| | | `b` | `2` | `2/AFTER/END` | **DIFF，rc=0** |
| | | `z`（零臂命中） | `AFTER/END` | 同 | SAME |
| **P2** `c008_p2_fn_echo_arm_return_tmp.php` | 函数内同形，链后 `return "R\n"` | `a` | `1/B=END` | `1/B=R/END` | **DIFF**：`return` 丢失 ⇒ 函数隐式 null ⇒ 拼接为空串 |
| | | `b` | `2/B=END` | `2/B=R/END` | **DIFF** |
| **P3** `c008_p3_fn_echo_arm_assign_tmp.php` | 函数内同形，链后「赋值 + return」 | `a`/`b`/`z` | `arm-empty/D=null/END` | `arm-empty/D={"tail":1}/END` | **DIFF**：链后**两条**语句整体丢失（fD 条件与 argv 无关，故三 arg 同读数） |
| **P4** `c008_p4_loop_echo_arm_tmp.php` | **foreach 体内**同形，链后仍有循环体语句 | `a`（走 `if` 首臂） | `L-1 x/END` | `L-1 x/L-after x/L-1 y/L-after y/END` | **DIFF**：不仅丢本轮链后语句，**整个循环只剩首迭代**（latch 一并丢失） |
| | | `b`（走 `elseif` 臂） | 同 PHP | 同 | SAME ⇒ 与 §3 发射形态一致（首臂 latch 断、非首臂走嵌套 else 再比较路径不受影响） |
| **C1** `c008_c1_if_else_arm_tmp.php` | `if/else` + 臂尾 echo + 链后 echo | `a`/`b`/`z` | 同 PHP | 同 | SAME（共因 1 的反例） |
| **C2** `c008_c2_arr_arm_tmp.php` | 无 else 链，臂尾数组追加，链后 return | — | `A={"e":["A"]}` | 同 | SAME（共因 2 的反例＝语料 `f032` 形） |
| **C3** `c008_c3_echo_not_last_tmp.php` | 无 else 链，臂内 echo **非**末条 | — | `arm1/E={"e":["A"],"tail":1}` | 同 | SAME（共因 2 精确到「臂尾末条」） |
| **C4** `c008_c4_void_call_arm_tail_tmp.php` | 无 else 链，臂尾末条为 `noop()` 调用 | — | `G={"tail":1}` | 同 | SAME（排除「任何忽略结果的语句」） |

**实测成本**：整门 8 次编译 + 18 次运行 = `elapsed=37s`（单形编译 ≈4s，运行 <1s）。

---

## 3. 机制（生成码直读，`ZIGPHP_AOT_KEEP_TEMP=1` 只读通道，零插桩零源码改动）

P1 的生成码（保留目录 `main.zig`，脚本仅 6 行故整文件 1255 行）：

```zig
// main.zig（生成码摘录，源行标注为实测 setSourceLocation 值）
    reg_5 = try runtime.php_identical(reg_3, reg_4);   // :3  $n === 'a'
    if (reg_5.toBool()) {
        reg_6 = runtime.Value.initString(static_strings[3]);
        _ = try runtime.php_echo(reg_6);               // :3  臂 1 尾 = echo
    } else {
        reg_9 = try runtime.php_identical(reg_7, reg_8);   // :3  $n === 'b'（elseif 展平为嵌套 if）
        if (reg_9.toBool()) {
            reg_10 = runtime.Value.initString(static_strings[5]);
            _ = try runtime.php_echo(reg_10);              // :3  臂 2 尾 = echo
        } else {
            reg_11 = runtime.Value.initString(static_strings[6]);
            _ = try runtime.php_echo(reg_11);              // **:4  链后的 echo "AFTER" 落在这里**
        }
    }
```

- `elseif` 被展平为「外层 if 的 else 里再嵌一个 if」，链的**隐式 else** 即最内层 `} else {`；
- 链后语句（源行 `:4`）被发射进这个隐式 else 块内，**而不是**链的 merge 块；
- 臂尾为 `echo` 时，臂内**没有**任何跳转到 merge 的 latch（`_ = try php_echo(...)` + 异常守卫后直接闭合块），故命中臂 ⇒ 跳过链后全部语句；
- 零臂命中 ⇒ 恰好走进隐式 else ⇒ 链后语句执行 ⇒ 这就是 P1/P2/P4 的 `arg=z` 判 SAME 的原因（**发射不缺，归属错**）。

与既有工单的关系（只陈述实测边界，不并案）：
- **CODEGEN-005 RC-4/RC-5「臂尾裸 break/continue 未发射」「臂尾 latch 交还」**：同一「臂尾 latch」承重环，但 005 的形都在**循环内**且臂尾是 break/continue；本形臂尾是 `echo`、链在任意作用域（P1/P2/P3 根本不在循环内）。
- **CODEGEN-006 形 7「二级 `cond_br` 终止符从未派发」**：本形 P4（循环内首臂）与之相邻，实测 P4 连带丢循环 latch，属同一症状面还是新面**未判定**。
- **是否 497edc6/0ff09cf/b21cdfd 引入的回归**：**未判定**（需历史代次各一次 `zig build` 重建对比，成本未实测）。语料面为 0 ⇒ 冻结基线的 `main.zig` md5 门无法判别，必须靠本门脚本。

---

## 3B. 第二面（f004 替身探针实测，2026-10-07 任务 #114）：臂条件整段未派发 + 链后语句整段未发射

§3 那一面是「**发射不缺、归属错**」。同一轮在 `fuzzy_scripts_720/tmp/f004_ro_unser_tmp.php`（永久替身探针）上直读生成码，量到第二面：**发射本身就缺**。

复现直读（零插桩，代次二进制 `1f15e4ce9b5c9cdaaef7cabf5efb9c76`）：

```bash
# 仓库根目录
ZIGPHP_AOT_KEEP_TEMP=1 timeout 120 zig-out/bin/php-interpreter --compile \
  --output=/tmp/x/aot_compile_f004_ro_unser_tmp fuzzy_scripts_720/tmp/f004_ro_unser_tmp.php
# 逐行发射计数（0 ⇒ 该源行的指令从未进入生成码）
grep -o 'f004_ro_unser_tmp.php", [0-9]\+' .zigphp_aot_build_<pid>/main.zig \
  | awk -F', ' '{print $2}' | sort -n | uniq -c | awk '$2>=205'
```

链结构：源 `:210-226` 是**无 `else`** 的 7 臂 `if/elseif`（派发 `class_const`/`priv_read`/`priv_write`/`prot_read`/`type_inherit`/`type_self`/`dyn_ro`），链后语句为源 `:227-233`（第二条 2 臂无 `else` 链）与源 `:234`（`echo "DONE\n"`）。

| 源行 | 内容 | 发射指令数 | 判读 |
|---|---|---|---|
| `:210` | `if class_const` 条件 | 3 | 派发 |
| `:214` | `elseif priv_read` 条件 | 3 | 派发 |
| `:216` | `elseif priv_write` 条件 | 3 | 派发 |
| `:218` | `elseif prot_read` 条件 | 3 | 派发 |
| **`:220`** | `elseif type_inherit` 条件 | **0** | **臂根本不可命中** |
| `:221` | type_inherit 臂体 `$show(...)` | 7 | 已发射但不可达 |
| **`:222`** | `elseif type_self` 条件 | **0** | **同上** |
| `:223` | type_self 臂体 | 7 | 已发射但不可达 |
| **`:224`** | `elseif dyn_ro` 条件 | **0** | **同上** |
| `:225` | dyn_ro 臂体 | 11 | 已发射但不可达 |
| `:227`/`:230` | 第二条链两臂条件 | 3/3 | 派发 |
| `:231` | val_dyn 臂体 | 11 | 已发射 |
| **`:232`** | val_dyn 的 `echo "slot=..."` | **0** | **整段未发射** |
| **`:234`** | 链后 `echo "DONE\n"` | **0** | **整段未发射** |

旁证（字符串侧，同一条生成码）：`"DONE\n"` 在字符串表 index 88，全文件只有 3 处 `static_strings[88]` 引用，分别挂在源行 `:178`/`:190`/`:196`（外层链的前三臂）⇒ 外层链第四臂（大 `||` 形）链后的 `:234` **从未产生任何 echo**。

后果（运行面实测，见 §2 同轮读数）：`priv_read`/`priv_write`/`prot_read`/`type_inherit`/`type_self`/`dyn_ro`/`val_self`/`val_dyn`/`class_const` 九形 AOT 全部**不输出 `DONE`**，其中 `type_inherit`/`type_self`/`dyn_ro` 连臂体都不执行（`$show` 的异常消息整行缺失），`val_dyn` 连 `slot=` 都缺失；`aot_rc` 仍为 0。

**对 §1 判据的更正**：§1 的四条共因（无 `else` ∧ 命中臂尾为 `echo` ⇒ 链后语句并入隐式 else）**不足以覆盖本面** —— 本面里受害臂的臂尾是 `$show(...)` 调用（非 `echo`），且丢失形态是「第 5 臂起的条件不再发射」+「链后语句零发射」，而非「并入隐式 else」。⇒ 修复判据必须同时覆盖两面，验收必须同时跑 §6 的 C008 门与本探针的逐行直读；任何只消解「臂尾 echo 归属」的改法，九形里至少 `type_inherit`/`type_self`/`dyn_ro`/`val_dyn` 仍会红。

臂数阈值提示（**未判定，仅登记读数**）：本链共 7 臂，前 4 臂条件发射、后 3 臂缺失；本门未做「臂数 = 4/5」二分，故「4」是巧合还是硬上界未知，落地前需单独二分。

---

## 4. 影响与风险

| 维度 | 实测结论 |
|---|---|
| 输出正确性 | 链后语句整体缺失（P1/P2/P3/P4），且**缩到 5 行 PHP 即可复现** |
| 静默性 | **rc=0**，无 warning、无编译错误 ⇒ 体验上「编译成功 + 运行成功」 |
| 类型/返回语义 | 声明 `: string` / `: array` 的函数在链后 `return` 丢失后**返回隐式 null 且不报 TypeError**（P2 空串、P3 `json_encode(null)`）⇒ 返回类型约束被绕过 |
| 控制流 | 循环内同形连带**丢失循环 latch**（P4 只跑首迭代） |
| 假绿风险 | 官方回归门 `run_regression.sh:43-49`（实测：`:44` 跑 PHP → `:45` 取 rc → `:46` 判非零 → `:47` 写 `SKIP`） 先跑 PHP，PHP 侧非零退出即写 `SKIP` 并**根本不编译 AOT**；语料唯一 SKIP 形 `f004` 的替身探针正是靠人肉逐形跑才发现本缺陷 ⇒ 语料面的「0 失败」对本形没有保护力 |
| 破坏式变更风险 | 修复属发射归属改动 ⇒ 可能移动全部语料的生成码（需重冻基线），**落地成本必须按全门链计**（见 §5） |

---

## 5. 修复路线（优先级 / 影响面 / 落地成本）

| 路线 | 内容 | 优先级 | 影响面 | 落地成本 |
|---|---|---|---|---|
| **R-A** | 发射侧：无 `else` 的 if/elseif 链，臂尾末条语句为 `echo` 时补「交还链 merge 块」的 latch（merge 目标 = 链后首块），使链后语句归属 merge 而非隐式 else | **P0** | 所有「无 else 链 ∧ 臂尾 echo」的 PHP（含 P1–P4 全四红形）；语料 68 枚理论发射可变（需实测是否逐字节中性） | 高：`native_linker.zig`（664KB）改动，改前必须 grep 既有臂尾 latch 模式；验收 = 本门 `same=18 diff=0` + 68 回归 + 漂移门 + `zig build test` |
| **R-B** | 发射期**金丝雀**：检测到「臂尾末条为 echo ∧ 链无 else ∧ 链后仍有语句」而 merge 归属指向隐式 else 时，编译期报错（禁止静默截断） | **P0**（止血优先，可与 R-A 并行） | 全语料零命中（语料面 0 ⇒ 不会误伤现有绿形） | 低：单点守卫，不改归属逻辑；把「静默错」变「显式失败」，同时是本形的回归哨兵 |
| **R-C** | 循环内同形（P4）与 CODEGEN-005/006 承重环的关系判定：同臂尾 latch 还是二级 `cond_br` 派发缺口 | **P1** | P4 一枚形；判定结果决定 R-A 是否需覆盖循环侧 | 中：影子轮（只读生成码 + 门读数），无需插桩 |
| **R-D** | 代次二分判定是否 10-05/10-06 三批提交（`b21cdfd`/`0ff09cf`/`497edc6`）引入 | **P1** | 决定优先级（回归 ⇒ 提级）与是否需回退局部改动 | 中：每代一次 `timeout 120 zig build` + 本门 37s，共 3–4 代；**需重建覆盖 `zig-out`，完成后必须回建当代次并复验 md5** |

**门控声明**：按宪法 §五/§六，R-A/R-B/R-C/R-D 全部需要老铁点头后才动源码；本轮**零源码改动**。

---

## 6. 复测路径（体验流程）

```bash
# 仓库根目录执行，代次二进制不变时可反复跑
timeout 300 bash fuzzy_scripts_720/tmp/c008_chain_tail_gate_tmp.sh
# 当前代次预期：C008_DONE same=10 diff=8 compile_fail=0 elapsed=37s
# 修复后预期  ：same=18 diff=0（四条控制臂必须保持 SAME，否则判据被砸）
```

永久探针（**勿删**，均带「红/绿」身份注释）：
`c008_p1_top_echo_arm_tmp.php`、`c008_p2_fn_echo_arm_return_tmp.php`、`c008_p3_fn_echo_arm_assign_tmp.php`、`c008_p4_loop_echo_arm_tmp.php`、`c008_c1_if_else_arm_tmp.php`、`c008_c2_arr_arm_tmp.php`、`c008_c3_echo_not_last_tmp.php`、`c008_c4_void_call_arm_tail_tmp.php`

---

## 7. 同轮附带发现（另一族，未最小化）

| 形 | 现象 | 读数 | 状态 |
|---|---|---|---|
| `elseif` 条件为**长 `||` 链**（9 元，跨物理行）且臂内含无 else 二级链 | **编译期硬失败** | `[AST-DIRECT-FAIL] function=__main__ unprocessed blocks: 23:logical_merge_25 24:logical_rhs_26 … 43:if_merge_47`（共 21 块） | 未最小化；PHP 侧同脚本正常 ⇒ 按 §七-8 第一条属 AOT 缺陷，禁止以简化脚本逃避 |
| 多构造并列探针（类方法 + 函数 + foreach 同文件，驱动链为无 else `elseif`） | **编译期硬失败** | `[AST-DIRECT-FAIL] … unprocessed blocks: 14:if_else_13 19:if_else_19` | 未最小化；注意失败块名即 `if_else_*`（隐式 else 块）⇒ 与本工单 §3 的「隐式 else 归属」同族，判定点待测 |

两者均**未**归入本工单的已证机制，仅登记原始读数与探针位置（`arm_chain_tail_probe_tmp3.php` 的 G 形、`chain_tail_cofactor_probe_tmp6.php`）；后续最小化时先跑「去掉某臂 ⇒ 是否仍失败」的逐臂剔除，再决定并案或另立。
