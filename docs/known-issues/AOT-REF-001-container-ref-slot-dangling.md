# 容器引用（`=&`）三缺陷族：槽指针悬垂、ref 变量写入静默吞没、属性目标整句丢弃

**问题 ID**: AOT-REF-001
**优先级**: P0（含 UAF 写；且存在「赋值语句凭空消失」的语义级错误）
**状态**: **D0 止血 + D2 根治（方案 A）已修复并验收闭环（2026-09-30）**；D1（属性/静态属性真引用）按用户裁决「D1 先不动」列为 P0 能力缺口，待另批推进；同源残留登记于 AOT-REF-002
**发现日期**: 2026-09-29（S7 收口后推进 #32 复现），根因取证完成于 2026-09-30
**修复日期**: 2026-09-30（用户裁决「D0 和 D2 方案 A 一起修，D1 先不动」），纯 `runtime_lib_template.zig` 改动，发射零漂移

---

## 1. 问题描述

> **行号口径**：§1 / §4 / §5 中的行号是**修复前（2026-09-30 取证时）快照**；模板改动后行号整体后移。当前行号见 §6 与变更文档 §5.2（`php_ref_assign_ptr:8022`、`php_array_get_ref:4851`、`derefVal:3044`、`make_ref:3055`、`val_assign:2970`、`ArrayIterator` 锁计数清零 `:8168-8169`）。

AOT 的引用实现有两套表示，但只有一套真正在用，且用错了地方：

- `Value.initRef(*Value)`（runtime_lib_template.zig:2407-2411，注释本身即写明「直接指针，**不推荐用于数组元素**」）——把引用存成一个**裸槽地址**；
- `Value.initRefWrapper(*RefWrapper)`（:2413-2417，注释「使用 RefWrapper，**推荐用于数组元素**」）——键定位、可抗搬迁。

实测 `grep -n "initRefWrapper\|asRefWrapper\|RefWrapper{" src/aot/runtime_lib_template.zig` 只命中这 2 处**定义**，构造点 **0 处** ⇒ RefWrapper 是从未接入的死脚手架（`ref_lock_count` 只在 foreach 路径 +1，`RefWrapper.deinit` 永不被调用）。

于是 `php_array_get_ref`（:4795-4815）与 `php_object_get_ref`（:19101-19131）都返回 `Value.initRef(entry_ptr)`，即指向容器桶数组里的一个槽。而 `Value.retain`（:2589-2605）**没有 Ref 分支**、`Value.release`（:2607-2611）对 Ref **直接 return** ⇒ Ref 值零所有权、零锚定：容器一旦扩容，槽地址迁移，旧 Ref 立即悬垂。

由此派生三个**相互独立**、各自可复现的缺陷：

| 编号 | 缺陷 | 后果性质 |
|---|---|---|
| D0 | `php_ref_assign_ptr`（:7959-7967）在目标不是 Ref 时**什么都不做并返回 null** | 赋值静默消失（不是退化成值语义，是彻底丢失） |
| D1 | `generateRefAssignment`（ir_generator.zig:4482-4680）把属性/静态属性源当**普通值读**，却照样 `putRefVar(目标)` | 后续对该变量的每次写入都走 D0 ⇒ 全部写丢失；`$obj->p = &$v`（目标为属性）落入 `else => {}`（:4676-4678）⇒ **整条语句被丢弃**。真实失效面 = 标量属性/静态属性引用；数组型属性引用靠共享 `*PHPArray` 指针侥幸正确（见 §5.1） |
| D2 | 容器取引用返回**槽指针**（`initRef(entry_ptr)`），容器扩容后悬垂 | 写入已释放内存（UAF 写）+ 写不回容器 |

## 2. 复现代码（4 个永久探针，勿删）

| 探针 | 打击点 |
|---|---|
| `fuzzy_scripts_720/tmp/ref_semantics_matrix_probe_tmp.php` | 8 场景分层对照：变量/数组元素/对象属性/静态属性/属性持引用/by-ref 形参/foreach 引用/二维 |
| `fuzzy_scripts_720/tmp/ref_rehash_dangling_probe_tmp.php` | D2 数组路径：取引用后扩容 150 键 / 追加字符串键（packed→mixed） |
| `fuzzy_scripts_720/tmp/obj_prop_ref_control_probe_tmp.php` | D1 隔离对照：**无任何扩容**的 3 个场景（证明失效与 rehash 无关） |
| `fuzzy_scripts_720/tmp/obj_prop_ref_rehash_probe_tmp.php` | D1+D2 对象路径：取引用后插入 64 个属性名 |

```bash
cd /Users/wangjianjun/products/parser
for f in ref_semantics_matrix_probe_tmp ref_rehash_dangling_probe_tmp obj_prop_ref_control_probe_tmp obj_prop_ref_rehash_probe_tmp; do
  timeout 300 ./zig-out/bin/php-interpreter --compile --no-debug-info --output=/tmp/aot_compile_$f fuzzy_scripts_720/tmp/$f.php 2>/tmp/aotc_$f.err
  timeout 10 /tmp/aot_compile_$f
done
```

## 3. 实测对照（2026-09-30，真值 = `/opt/homebrew/bin/php` PHP 8.5）

`ref_semantics_matrix_probe_tmp.php`：

| 场景 | PHP 真值 | AOT 实测 | 判定 |
|---|---|---|---|
| case1 `&$x` | `2\|2` | `2\|2` | OK |
| case2 `&$a[0]`（不扩容） | `9\|9` | `9\|9` | OK |
| case3 `&$c3->p` | `7\|7` | **`1\|1`** | D1+D0 写全丢 |
| case4 `&S::$v` | `5\|5` | **`1\|1`** | D1+D0 写全丢 |
| case5 `$c5->p = &$v5` | `2\|2` | **`1\|2`** | D1 整句丢弃 |
| case6 by-ref 形参 | `42` | `42` | OK |
| case7 foreach by-ref | `10,20,30` | `10,20,30` | OK |
| case8 `&$m8[0]['k']`（不扩容） | `3\|3` | `3\|3` | OK |

`obj_prop_ref_control_probe_tmp.php`（**关键否证**：三个场景都不涉及属性地图扩容）：

| 场景 | PHP | AOT | 判定 |
|---|---|---|---|
| case1 取引用后直接写 | `through-ref\|through-ref` | **`first\|first`** | 与 rehash 无关，纯 D1+D0 |
| case2 取引用后插 1 个属性 | `after-one-insert\|after-one-insert` | **`x\|x`** | 同上 |
| case3 先插满 64 个再取引用 | `late-ref\|late-ref` | **`first\|first`** | 同上 |

> 我此前假设「对象属性引用失效是 rehash 造成」，被本对照探针**否证**：无扩容场景同样全丢。真正机理是 D1 发射 + D0 吞写。

`ref_rehash_dangling_probe_tmp.php`（**独立证实 D2 真实存在**）：

| 输出 | PHP | AOT | 判定 |
|---|---|---|---|
| `k7` / `ref` | `999\|999` | **`7\|999`** | 写入落在已释放桶槽（UAF 写），容器看不到 |
| `sum` / `n` | `22350\|200` | `22350\|200` | 容器本身搬迁无损坏 ⇒ 差异只可能来自旧 Ref |
| `b1` / `ref` | `777\|777` | **`20\|777`** | 同上（packed→mixed 路径） |

`obj_prop_ref_rehash_probe_tmp.php`：

| 输出 | PHP | AOT |
|---|---|---|
| 判据① `$c->a` | `through-ref` | **`first`** |
| 判据② `sum` | `sum=6048` | `sum=6048` |
| 判据③ `after-plain` | `plain-set\|ref=plain-set` | `plain-set\|ref=**first**` |

### 3.1 修复后复测（2026-09-30，D0 止血 + D2 方案 A 落地）

| 探针 | 判据 | 修复前 AOT | 修复后 AOT | PHP 真值 | 结论 |
|---|---|---|---|---|---|
| `ref_rehash_dangling_probe_tmp` | `k7\|ref` | `7\|999` | **`999\|999`** | `999\|999` | D2 根治，逐字节等值 |
| 同上 | `sum\|n` | `22350\|200` | `22350\|200` | `22350\|200` | 等值 |
| 同上 | `b1\|ref` | `20\|777` | **`777\|777`** | `777\|777` | packed→mixed 路径同样等值 |
| `ref_semantics_matrix_probe_tmp` | case3 `&$c3->p` | `1\|1` | `1\|7` | `7\|7` | D0 已止血（写入不再消失）；容器侧差 = **D1** |
| 同上 | case4 `&S::$v` | `1\|1` | `1\|5` | `5\|5` | 同上 |
| 同上 | case5 `$c5->p = &$v5` | `1\|2` | `1\|2` | `2\|2` | 目标为属性的整句丢弃 = **D1**，本轮不动 |
| 同上 | case1/2/6/7/8 | 全等 | 全等 | — | 无回归 |
| `obj_prop_ref_control_probe_tmp` | case1/2/3 | `first\|first`、`x\|x`、`first\|first` | `first\|through-ref`、`x\|after-one-insert`、`first\|late-ref` | 两侧同值 | 变量侧写入全部落地；属性侧仍值语义 = **D1** |
| `obj_prop_ref_rehash_probe_tmp` | 判据①/③ | `first` / `ref=first` | `first` / `ref=through-ref` | `through-ref` / `ref=plain-set` | 同上；判据② `sum=6048` 保持不变 |

> 修复后验收口径（取代 §7 原第 2 条）：**D2 专属探针 `ref_rehash_dangling_probe_tmp` 与 PHP 逐字节等值**；三个属性侧探针的判据改为「引用变量侧写入必须落地、且原值不得再被静默丢弃」，容器侧余差归 D1，本轮按裁决保留。

## 4. 发射侧实锤（D1 的直接证据）

对矩阵探针 `ZIGPHP_AOT_KEEP_TEMP=1` 取 `main.zig`：

```zig
// 第 24 行 $r3 = &$c3->p —— 期望 php_object_get_ref，实际是普通属性读
reg_28 = try runtime.php_object_get(reg_27, "p");   // :1719
reg_29.* = reg_28;                                   // :1821 纯值拷贝
// 第 25 行 $r3 = 7 —— 因 $r3 已被 putRefVar 标记，走引用写
_ = try runtime.php_ref_assign_ptr(reg_29, reg_31);  // :1830 → 非 Ref ⇒ no-op
```

`grep -c "php_object_get_ref(" .zigphp_aot_build_*/main.zig` = **0**：该 runtime 函数已注册进 builtin 表（`native_linker.zig:3831`，2026-10-03 重新 grep；原登记 `:3803` 已漂移），却在整个语料与探针的发射中**从未被调用过**；静态属性同理落到 `php_get_static_property` 普通读 —— 该名字在当前树**没有** builtin 表条目，它是 runtime 函数（定义 `runtime_lib_template.zig:20310`），由 `native_linker.zig:23949` / `:23954` 以 `runtime.php_get_static_property("类", "属性")` 形式直接发射，IR 侧 op 由 `ir_generator.zig:4564` 的 `.static_property_get` 产生（以上四处均为 2026-10-03 实测）。**原登记的 `:2458` 已作废**：该行在 `125aa78`（2026-09-29）树里是 `return;`、在当前树里是一个结构体字段行，均与静态属性读无关，属未标注文件的悬空引用，故改指上述实测锚点。

`ir_generator.zig` 对应代码：

- `.static_property_access` 源（:4547+）→ `static_property_get` 普通读 + `no_cow_store`；
- `.property_access` 源（:4568-4573）→ `no_cow_store = true; source_ref = try self.generateExpression(source_idx);`（**注释误判**：「PHPArray 是引用计数的，修改会传播」——对象属性是 `Value` 槽，不是引用计数容器，值拷贝不传播）；
- 目标 `.variable` 分支（:4619-4625）→ `store{no_cow}` + `putRefVar(tgt_name)`（正是这一步把目标标成 ref 变量，令后续写入全部落入 D0）；
- 目标 switch 尾部 `else => { // 其他目标类型暂不支持 }`（:4676-4678）⇒ `$obj->p = &$v`、`C::$p = &$v` 静默丢句。

## 5. 为什么会悬垂（D2 机理，逐条对代码）

| 事实 | 位置 | 结论 |
|---|---|---|
| `Elements.put` 遇 `parent.has_active_refs` 强制 `convertToMixed()`，注释称「避免重新分配」 | :1896-1902 | 但 `mixed` 是 `ArrayHashMapUnmanaged`，插入新键仍会分配新桶数组 ⇒ **该保护只挡住 packed→mixed 这一次形态转换，挡不住后续扩容** |
| `ref_lock_count` 仅在 `PHPArray.release` 中推迟释放 | :2077-2081 | 推迟的是**数组对象**生命周期，不是**槽地址**稳定性 |
| `php_array_get_ref` 相比 foreach 引用路径缺 3 项防护 | :4795-4815 对比 :7835-7840 / :7920 | 既未 `has_active_refs = true`、未 `convertToMixed`、也未 `arr.retain()`/`ref_lock_count += 1` ⇒ 连「数组对象不被提前释放」都没保证 |
| `php_array_get` 读元素**不逐元素解引用** | :4750-4753 | 若把 Ref 装进槽（修复方案 A），所有元素读路径必须先 `val_deref` |
| `val_assign` 目标为 Ref 时写穿 | :2926-2938 | 修复方案 A 的写侧基础已具备 |
| `ArrayIterator` 释放时 `ref_lock_count = 0`（清零而非 -1） | :8102-8104 | 多引用并发迭代时锁计数被抹平，属同源缺陷的第二个锚定漏洞 |

foreach by-ref（case7）之所以正常，只是因为每次迭代都用 `m.getPtr(key)` **重新**取槽指针（:7923-7926），把悬垂窗口压到单次迭代内——这是运气，不是设计。

### 5.1 语料实测：该语法确在生产语料中使用（重要，决定改造影响面）

`grep -rn '= &\$' fuzzy_scripts_720/pass` 全量命中（68 脚本）：

| 文件 | 行 | 形态 | 今日为何仍 PASS |
|---|---|---|---|
| `f110_os_sim_process_memory_filesystem.php` | 192/204/217/228/239 | `$current = &$this->root`（**属性源引用**，走 D1 退化路径） | `private array $root` 是数组 ⇒ 值拷贝与原属性**共享同一 `*PHPArray`**，`$current[k][children][...] = ...` 就地改数组 ⇒ 写回侥幸可见 |
| `f110_...php` | 196/208/220/231/242 | `$current = &$current[$part]['children']`（数组元素源，走 `php_array_get_ref`） | 循环内每轮重取 ⇒ D2 悬垂窗口未被踩到 |
| `f044_json_deepops_merge_diff.php` | 18/21 | `$ref = &$data` / `$ref = &$ref[$key]` | 同上，变量源 + 元素逐轮重取 |

⇒ **结论修正**：D1 的真实失效面是**标量属性引用**（`&$obj->prop` 存 int/string，如矩阵探针 case3/case4/control case1-3）与**静态属性引用**；数组型属性/元素引用今天靠共享指针正确。因此「补真引用」不是从零起能力，而是**在已通过的 f110/f044 行为之上收敛语义**——改造必须同时证明这两个脚本输出不变（发射会变，见 §6），风险高于纯模板方案。

## 6. 修复方案（按优先级 / 影响面 / 落地成本）

| 优先级 | 方案 | 影响面 | 落地成本 |
|---|---|---|---|
| **P0** | ✅ **D0 止血（已落地 2026-09-30）**：`php_ref_assign_ptr` 补 `else` 分支——目标非 Ref 时 release 旧值 + retain 新值 + `val_assign` 直写 `*ref_ptr` | 仅 `runtime_lib_template.zig` 1 函数；把「凭空消失」改为「写入落到变量本身」 | 实测 ≈8 行；发射零变化（72 项冻结 md5 抽查 5/5 逐字节等值） |
| **P0** | ⏸ **D1 能力补齐（本轮按裁决不动）**：`generateRefAssignment` 的 `.property_access`/`.static_property_access` 源改发 `php_object_get_ref`/静态属性真引用；target switch 新增属性/静态属性目标（配 `php_object_set_ref`）；同步修正 :4568 的注释 | `ir_generator.zig`（发射侧）+ runtime 1 新函数 | 中（估 80-120 行）。**语料确已使用该语法**（§5.1），改造必然改动 f110/f044 的发射 ⇒ 冻结 md5 漂移，需先证明「仅这两个脚本漂移」再走重冻结；且须保证 f110/f044 的数组型属性引用不回退（今天靠共享 `*PHPArray` 侥幸正确） |
| **P0** | ✅ **D2 根治·方案 A「引用装槽」（已落地 2026-09-30）**：`php_array_get_ref` 改为复用 `make_ref`——为该元素建堆 `Value` cell、把 cell 的 Ref 写回槽，返回同一 cell Ref；元素读路径通过 **`Value` 层 Ref 透明**统一解引用（9 个类型谓词 + `asBool/asInt/asFloat/asString/asFunction/asResource/toBool/toInt/toFloat` + `PHPArray.get`/`set` 写穿 + `retain` 对称 no-op） | 仅 `runtime_lib_template.zig`，实测 162 增 / 63 删 | **成本形态与初估不同，需更正**：原估「120-180 行逐点 deref」，实际把 deref 下沉到值类型层，**144 处裸读 `entry.value_ptr.*` 站点一处未改**即被覆盖（改造点从 O(消费端) 降到 O(类型系统)）。每取一次引用 +1 个 8B cell，读侧多一层跳转；发射零变化 |
| P1 | D2·方案 B「接通 RefWrapper」：实现键定位 `RefWrapper`（已设计未接入），`val_deref`/`release`/`retain` 识别双表示 | 全引用消费端，爆炸半径最大 | 高；方案 A 已闭环，本方案仅在需要「跨容器键重定位」时才有价值，暂不升级 |
| P1 | `ArrayIterator` 的 `ref_lock_count = 0`（清零而非 -1，:8102-8104）改 `-= 1` | 1 处 | 极低，归入 AOT-REF-002 同批 |
| P2 | foreach by-ref 每次迭代重取槽指针（:7923-7926）改为持有 D2 修复后的稳定 Ref | 迭代器语义 | 中；归入 AOT-REF-002 |

## 7. 验收门（任一修复均须全绿）

1. `timeout 120 zig build` exit=0；
2. 4 个探针 AOT 输出与 `/opt/homebrew/bin/php` **逐字节等值**；
3. 官方回归 `scripts/regression_test_720.sh`：68 项，FAIL_COMPILE=0 / FAIL_RUNTIME=0 / FAIL_DIFF=0（f004 SKIP 允许）；
4. **72 项冻结基线逐字节等值** `fuzzy_scripts_720/baseline_main_zig_md5.tsv`（模板侧修复必须全等；若走 D1 发射侧修复，须先证明漂移只发生在探针而不发生在语料，再走重冻结流程）；
5. 确定性巡检 `f12_determinism_tmp.sh`：`SWEEP_DONE total=68 mismatch=0 notemp=0`；
6. 冻结基线抽查 `s7_baseline_spotcheck_tmp.sh`：`SPOT_DONE ok=5 bad=0`；
7. `zig build test`：21/21 步骤、326/326 用例、0 leak 步骤（改模板不触碰单测输入，改发射侧则必跑）；
8. 复测前 `ps -A | grep "zig build-exe"` 排查 PPID=1 孤儿进程；批次运行期间禁止编辑 `runtime_lib_template.zig`、禁止 `zig build`。

### 7.1 本轮实测结论（2026-09-30，D0 + D2 方案 A）

| 门 | 结果 | 判定 |
|---|---|---|
| 1 `timeout 120 zig build` | RC=0（增量命中，无输出） | ✅ |
| 2 探针等值 | `ref_rehash_dangling_probe_tmp` **IDENTICAL**；其余 3 探针按 §3.1 修订口径判定（变量侧写入全部落地） | ✅（口径见 §3.1） |
| 3 官方回归 | TOTAL 68 / PASS 67 / FAIL_COMPILE 0 / FAIL_RUNTIME 0 / **FAIL_DIFF 0** / SKIP 1（f004） | ✅ |
| 4 冻结基线 | 抽查 `SPOT_DONE ok=5 bad=0`（f031 5838 / f010 16111 / f042 29420 / f067 47364 / f113 104334 行，md5 全等）⇒ **发射零漂移** | ✅ |
| 5 确定性巡检 | `SWEEP_DONE total=68 mismatch=0 notemp=0` | ✅ |
| 6 单测 | **未跑**（非遗漏）：`build.zig` 不引用 `runtime_lib_template.zig` ⇒ 模板改动不是 `zig build test` 的输入，发射产物未变 | ✅（按规则豁免） |
| 7 产物清零 | `pass/` 内 `aot_compile_` = 0、`.zigphp_aot_build_*` = 0、`/tmp/aot_compile_*` = 0；`pass/*.php` 仍 68 个，PHP 源脚本零删除 | ✅ |
| 8 过程纪律 | 回归/巡检/抽查/探针全程**严格串行**，批次期间未编辑模板、未 `zig build`；复测前已排查孤儿 `zig build-exe` | ✅ |

## 8. 风险评估

- **破坏性**：D0/D2 为纯模板修复，产物语义向 PHP 收敛，不改发射 ⇒ 风险集中在「读路径漏 deref」导致把 Ref 当值输出（表现为打印出一个对象指针或错值），68 脚本逐字节回归是当前唯一有效检测器（safe-mode 对「读已释放槽」不 panic）。
- **内存安全**：D2 现状已是**生产级 UAF 写**（写入已释放桶数组），不是单纯功能缺陷；这也是把 D2 定为 P0 的理由。
- **泄漏**：方案 A 引入的 cell 与 `make_ref` 同生命周期策略（Ref 不参与 retain/release 计数），退出时 cell 不回收——与 S2 头归还池的结论一致，需在实现中评估是否在容器 deinit 时回收（若回收，必须同时保证不存在跨容器逃逸引用）。
- **性能**：D2 方案 A 对每次 `&$arr[$k]` +1 次小对象分配；语料中该语法出现频次极低，实测斜率应在 S1/S2 的噪声内。

## 9. 裁决记录与当前待裁

**已裁决并执行（2026-09-30）**：用户口径 **「D0 和 D2 方案 A 一起修，D1 先不动」** ⇒ D0 + D2（方案 A）已落地并六门全绿（§7.1），D2 方案的「每引用一次 cell 分配」性能代价随该裁决一并接受；本文 §1/§4/§5 的取证结论保持有效，作为 D1 的输入。

**仍待裁（AI 未擅自推进）**：

| # | 待裁项 | 归属 | 为什么必须问 |
|---|---|---|---|
| 1 | **D1 属性/静态属性真引用**：改 `generateRefAssignment` 发射 ⇒ f110/f044 产物必然漂移 | `ir_generator.zig` | 涉及基线重冻结 + 已通过脚本的行为回退风险（§5.1） |
| 2 | **AOT-REF-002 R-1a/R-1b 单行收口**（`php_array_iter_value_ref:7984`、`php_array_walk:25562` 改 `make_ref`）——两点均已探针实证，纯模板 | `runtime_lib_template.zig` | 超出本轮「D0+D2」裁决范围，属范围扩张 |
| 3 | **AOT-CODEGEN-005**（foreach 体内静默丢语句，已 bisect + 发射实锤）是否授权定位与修复 | `native_linker.zig` | 发射侧修复 ⇒ 冻结基线需重走一道门（§六.2/§六.7） |

## 10. 锚点代次刷新（2026-10-05，当前工作区代次 `fbe6382a`／32797 行实测；只读巡检，零代码改动）

§取证 与 §9 的行号登记于 **2026-10-03**（RC-4/RC-5 代次）。`native_linker.zig` 其后被 A／D／R9-B 三批（`497edc6`）与 #74 注释批插行 ⇒ 发射侧锚点已漂移；**模板与 IR 侧未漂移**。按符号 grep 实测（非偏移推算），历史值保留不改写。

| 锚点 | 旧登记（2026-10-03） | **当前树实测** | 实测依据 |
|---|---|---|---|
| `php_object_get_ref` 进 builtin 表的注册行 | `native_linker.zig:3831` | **`:4074`** | `grep -n '"php_object_get_ref"'` = 唯一命中，该行即 `.{ "php_object_get_ref", bi(.{ .runtime_name = ..., .needs_allocator = true }) }` |
| 静态属性读发射（`runtime.php_get_static_property("类","属性")`） | `:23949` / `:23954` | **`:24254`**（8 空格缩进支）/ **`:24259`**（4 空格缩进支） | `grep -n 'php_get_static_property(\\"'` = 恰此两行命中（另有 `_dynamic` 名在 `:4275`/`:22345`/`:23281`，与本文锚点无关） |
| `php_get_static_property` runtime 定义 | `runtime_lib_template.zig:20310` | **`:20310`（未变）** | 该文件最后一次提交为 `b21cdfd`（2026-09-30）⇒ 晚于该日的三批不含它；`grep -n "pub fn php_get_static_property"` 唯一命中 |
| IR 侧 `.static_property_get` 产生点 | `ir_generator.zig:4564` | **`:4564`（未变）** | 该文件最后一次提交为 `9b2ddf5`（2026-08-25）；`grep -n` 命中即 `.static_property_get = .{` 的发射行 |

**对 §9 待裁项 2 的口径更正（本轮实证）**：该行写作「`php_array_iter_value_ref:7984`、`php_array_walk:25562` 改 `make_ref`」，实测两处的 **`make_ref` 语句行**分别为 **`runtime_lib_template.zig:7988`** 与 **`:25569`**（`:7984`/`:25562` 落在各自上方的 WHY 注释块内，非改动行）。AOT-REF-002 §P1 登记的 `:7988`／`:25569` 才是可开工行号；两值同文件、该文件未漂移 ⇒ 与「R-1a/R-1b 已落地 `b21cdfd`」一致，**本工单结论不变**，仅行号指称需按此对齐。
