---
工单: AOT-PERF-001
标题: AOT 产物运行期性能基线（默认 release_small 档位 + 逐指令全局变量/装箱 Value 热点）
状态: 已立项（2026-10-04），**未动任何代码**，三项决策待裁决
发现来源: AOT-CODEGEN-005 RC-5 facet-2 落地后的 do-while 侧「站点③」审计（见 [AOT-CODEGEN-005](AOT-CODEGEN-005-foreach-body-if-arms-lost.md) §4「do-while 侧站点③ 审计」与 §7 行 17）
关联: [AOT-MEM-001](AOT-MEM-001-phpstring-header-and-property-key-retention.md)（`retain/release` 所有权链路）、[AOT-CODEGEN-004](AOT-CODEGEN-004-recursion-stack-overflow.md)（状态机与递归边界）
---

# AOT-PERF-001：默认优化档位与发射侧逐指令热点

## TL;DR

用同一份脚本、同一棵树（工作区 blob `3ae7b34e`）、同一台机器实测三条独立结论：

1. **档位杠杆**：AOT 默认 `optimize_level = .release_small`（`src/aot/compiler.zig:140`），只在生成码 `> 200_000` 字节时被 `src/aot/native_linker.zig:32446`（当代次实测唯一 `200_000` 命中；旧引 `:32195` 已失效）静默升级为 `release_fast`。**小脚本拿不到这个升级** ⇒ 同一产物源码在纯计算负载上慢 **3.4 倍**、数组负载上慢 **2.6 倍**。
   - **收益边界实测（任务 #94）**：该门限对 **68 语料已 100% 命中**（语料最小 `main.zig` = `f040_flyweight_forest_pool` **278,560 bytes**）⇒ 阈值下调路线在语料内**无剩余收益**，只覆盖 `<200KB` 脚本；反之**改默认 `optimize_level`** 不等价（它同时换 IR pass 集），实测代价 = 67/67 生成码漂移 + 19/67 红（见 §4 两行拆分与 [AOT-CODEGEN-007](AOT-CODEGEN-007-function-inlining-param-args-lost.md) §3.5）。
2. **AOT↔解释器基线**：即便 `release_fast`，AOT 在当前语料形态上**仍慢于 `/opt/homebrew/bin/php`**（opcache 关、JIT disable 的 PHP 8.5.8）：纯整数循环 **约 20–29 倍**、数组写/迭代负载 **约 2.4–3.4 倍**。差距不在循环结构，而在**每条指令的发射几何**（见 §3）。
3. **函数级否决位的代价比预想小**：`has_do_while` / `has_switch` / `has_match` / `has_exception_handler` / `has_recursive_call` 命中 ⇒ **整个函数**放弃原生 label 循环、退回 `switch (current_block)` 逐块派发。在同一工作量的 A/B 下实测只贵 **+2%～+4.7%** ⇒ 优先级从「性能 P0」下调为「语义/覆盖 P2」（真正的性能大头是 §3 的三条热点）。

**本页所有数字都是实测**，方法、脚本源码、命令逐字登记于 §1，任何人可复跑。本轮**一行代码未改**，改档位与改发射均属 §六 需先点头的决策（见 §7）。

---

## 1. 复现方法与量测口径

**环境**：`Darwin 24.6.0 arm64`（Apple Silicon），`/opt/homebrew/bin/php` = **PHP 8.5.8 (cli) NTS**，`opcache.enable_cli=0`、`opcache.jit=disable`（即 PHP 跑**纯解释器**，与语料真值口径一致）。AOT 侧 = 仓库根目录 `./zig-out/bin/php-interpreter --compile --no-debug-info`（`--no-debug-info` 为语料回归同款开关）。

**计时**：`/usr/bin/time -p <cmd>` 取 `real`，逐脚本 3 轮；首轮普遍偏高 0.05～0.4s（冷 FS/page cache），**结论一律取后两轮的一致值**。PHP 进程启动成本实测 `php -r 'echo 1;'` ≈ `real 0.06`（`user 0.04`），做差时须扣掉。

**四条一次性 bench（源码逐字登记，便于复跑；跑完即删，不入库）**：

```php
<?php
// /tmp/bench_sm_tmp.php —— 数组写 + foreach 迭代（200k 规模）
$n = 200000;
$b = [];
for ($i = 0; $i < $n; $i++) { $b['k' . $i] = $i; }
$w = 0; $x = [];
foreach ($b as $key => $val) { $w++; $x[$w . "_0"] = 0; }
echo "SM visited={$w} count_x=" . count($x) . "\n";
```

```php
<?php
// /tmp/bench_wh_tmp.php 与 /tmp/bench_dw_tmp.php —— 外层 for + 臂内嵌循环（200k 规模）
// 两份**逐字同构**，唯一差别是内层关键字 while（wh）/ do-while（dw）⇒ 用于 A/B 发射策略
// wh: 内层 while ($k < 2) { ... }      dw: 内层 do { ... } while ($k < 2);
```

```php
<?php
// /tmp/bench_num_tmp.php —— 纯整数累加（无数组、无字符串）
$n = 5000000;
$s = 0;
for ($i = 0; $i < $n; $i++) {
    $s += $i * 2 + 1;
}
echo "NUM s={$s} n={$n}\n";
```

**输出等值前置校验**（否则计时无意义）：`/opt/homebrew/bin/php` 与两份 AOT 产物对 `bench_sm_tmp` 的输出**逐字节等值**（`cmp` 通过，各 33 字节）；`bench_num_tmp` 三方均输出 `NUM s=25000000000000 n=5000000`。

**线性度校验**（排除「快得反常」的假读数）：PHP 纯整数循环 `n=1M/5M/20M/40M/400M` 的 `real` = `0.05 / 0.07 / 0.15 / 0.26 / 2.27` ⇒ 扣除启动后**边际约 5.5 ns/迭代且线性**，读数可信（也说明 PHP 8.5 的标量 VM 确实快，不是我们测错）。

---

## 2. 实测结果

### 2.1 档位轴（同一生成码，`release_small` ↔ `release_fast`）

3 轮 `real` 原始值 + 产物体积：

| bench（形态） | 生成码 `main.zig` | ReleaseSmall（**默认**） | ReleaseFast | 加速比 | 产物体积 RS→RF |
|---|---|---|---|---|---|
| `bench_sm_tmp`（数组写 + foreach） | 87,483 B（默认档实测） | `0.46 0.45 0.45` | `0.18 0.17 0.17` | **2.65×** | 527,968 → 750,368（**+42%**） |
| `bench_wh_tmp`（for + 内嵌 while，原生循环） | 未取（同量级） | `0.66 0.64 0.63` | `0.24 0.23 0.24` | **2.78×** | 548,864 → 766,784（+40%） |
| `bench_dw_tmp`（for + 内嵌 do-while，状态机） | 未取（同量级） | `0.67 0.68 0.67` | `0.24 0.24 0.24` | **2.83×** | 548,736 → 766,760（+40%） |
| `bench_num_tmp`（纯整数累加 5M） | 50,892 B | `3.26 2.80 2.79` | `1.13 0.81 0.81` | **3.44×** | 432,576 → 602,240（+39%） |

**默认档实测（决定性）**：`bench_sm_tmp` 用**不带 `--optimize` 的默认命令**编译 ⇒ 产物 527,952 字节（与上表 ReleaseSmall 列一致）、`real 0.89(冷) 0.44 0.45` ⇒ **默认确实跑 ReleaseSmall**，因为其生成码 87,483 B < 200,000 B，逃逸门未触发（该门在当代次实测为 `:32446`；此处的 `:32195` 属更早代次锚点，保留作历史读数，见 §8.2.1）。

**编译墙钟代价**（同一 bench，3 轮取稳）：ReleaseSmall `real 4.04 / 4.01`，ReleaseFast `real 7.19 / 7.13` ⇒ **+78%**。

**语料侧暴露面（实测，不是外推）**：200KB ≈ **4,000～4,700 生成行**（按实测 42～50 B/行换算）。冻结基线 `fuzzy_scripts_720/baseline_main_zig_md5.tsv` 72 项的生成行数为 min `5,496` / 中位 `30,020` / max `1,108,387`，且实测最小语料脚本 `f040_flyweight_forest_pool` = **5,606 行 / 278,560 字节**（> 200,000）。⇒ **68 语料与全部长期探针都已落在逃逸门之上，回归测的一直是 ReleaseFast**；受档位拖累的只有「生成码 < 200KB」的小脚本（本工单四条 bench 即属此类，50–87KB）。

### 2.2 AOT ↔ PHP 解释器基线（`release_fast` 为 AOT 最好档）

| bench | PHP 8.5.8（解释器，JIT 关） | AOT ReleaseFast | AOT 默认（ReleaseSmall） |
|---|---|---|---|
| `bench_sm_tmp` | 0.06（3 轮 `0.17 0.06 0.06`，首轮冷） | 0.17 ⇒ **2.8× 慢** | 0.45 ⇒ **7.5× 慢** |
| `bench_wh_tmp` | 0.07 | 0.23 ⇒ **3.3× 慢** | 0.64 ⇒ **9.1× 慢** |
| `bench_dw_tmp` | 0.07 | 0.24 ⇒ **3.4× 慢** | 0.67 ⇒ **9.6× 慢** |
| `bench_num_tmp`（5M，边际扣启动） | ≈ 0.02 ⇒ ~5 ns/迭代 | ≈ 0.75 ⇒ ~150 ns/迭代（**约 29×**） | ≈ 2.75 ⇒ ~550 ns/迭代（**约 100×**） |

> 口径提醒：AOT 侧包含自身进程启动（毫秒级，可忽略）；PHP 侧 0.06 已含 0.04～0.05 的启动成本，故数组负载的真实差距比表内更大而非更小。

### 2.3 函数级否决位的代价（原以为是 P0，实测不是）

| 对照 | 内层关键字 | 发射策略（`main.zig` 逐字计数） | ReleaseSmall | ReleaseFast |
|---|---|---|---|---|
| `bench_wh_tmp` | `while` | 原生 label 循环 | 0.63 | 0.23 |
| `bench_dw_tmp` | `do-while` | `switch (current_block)` 状态机 | 0.67（**+6.3%**） | 0.24（**+4.3%**） |

⇒ 状态机回退在**该形态**上只贵几个百分点（回边派发被循环体内的全局变量开销淹没）。**否决位真正的代价是语义/覆盖面**（`generateDoWhileFromLabels` 整条不可达，见 CODEGEN-005 §4 审计），不是本表数字。

---

## 3. 发射侧热点取证（读生成码，未做分离量测 ⇒ 标注为「代码证据」而非「百分比」）

`bench_num_tmp.php` 的 `main.zig`（KEEP_TEMP，50,892 字节）循环体逐字摘录，每迭代一次：

```zig
    __for_0: while (true) {
    runtime.setSourceLocation("/private/tmp/bench_num_tmp.php", 5);   // ← 每条指令一次，共 12 次/迭代
    reg_3.release(runtime.runtime_allocator);
    reg_3 = getGlobalVar("$i");                                       // ← 按名字查表 + retain
    ...
    reg_5 = try runtime.php_lt(reg_3, reg_4);                         // ← 装箱 Value 上的通用比较
    if (!(reg_5.toBool())) { break :__for_0; }
    reg_6.release(runtime.runtime_allocator);
    reg_6 = getGlobalVar("$s");
    reg_8 = runtime.Value.initInt(2);
    reg_9 = try runtime.php_mul(reg_7, reg_8);
    reg_11 = try runtime.php_add(reg_9, reg_10);
    reg_12 = try runtime.php_add(reg_6, reg_11);
    try setGlobalVar("$s", reg_12);                                   // ← 按名字写表 + 引用链解析
    reg_14.release(runtime.runtime_allocator);
    reg_14 = try runtime.php_increment(reg_13);                       // ← $i++
```

三处可分离热点（按怀疑程度排序，**均尚未做单变量量测**）：

| # | 热点 | 代码证据 | 备注 |
|---|---|---|---|
| H1 | **全局变量按名字寻址**：顶层脚本的每个变量读写都走生成的 `getGlobalVar(name)` / `setGlobalVar(name, value)`。读侧先串比 `$this`、再 `global_vars.get(name)`（字符串哈希 + 探测）+ `retain()`；写侧更重 —— 先 `global_vars.get` 判 Ref、`resolveRefSource(name)`、`setGlobalVarDirect`，非引用名还要 `findAllRefsToSource(source, &refs_buf)` **扫描全部引用名** | 本 bench 每迭代 ≈ 4 次读 + 2 次写；`$i++` 一个语句就两次 `getGlobalVar` | PHP 把编译期变量编译成 **typed CV slot 下标寻址**，一次数组索引。这是 5 ns vs 150 ns 量级差的首要嫌疑 |
| H2 | **标量装箱**：IR **已带类型**（`--dump-ir` 实测为 `.{ .i64 = void }`，如 `const.i64 3`、`phi` 结果），但发射一律降级为 `runtime.Value` + 通用 `php_add/php_mul/php_lt/php_increment` + 每临时量一次 `.release(allocator)` | 上列摘录 5 个 `reg_*` 全是 `Value` | 需要「IR 类型为 int 且可静态证明无引用/无类型漂移 ⇒ 走未装箱 i64 快路」的特化 |
| H3 | **每指令 `setSourceLocation`**：三个热路径发射点（`native_linker.zig:19436`、`:20524`、`:22921`）无条件逐指令打印。运行时实现很轻（`runtime_lib_template.zig:340` = 两次 threadlocal 赋值），但本 bench 每迭代 **12 次**、5M 迭代 = 6,000 万次调用 | 摘录首行注释 | 应只在「可抛出/可报错」的指令处发射，或在循环内按源码行游程合并 |

**读数更正（2026-10-04，H1 侧）**：为归因热点新建的探针 `fuzzy_scripts_720/tmp/perf001_hotspot_probe_tmp.php` 有三门 mode，**mode=1（顶层全局循环，实测 0.42s）读数作废** —— 该形状命中 [AOT-CODEGEN-006](AOT-CODEGEN-006-elseif-chain-arm-loop-lost.md)（if/elseif/else 末臂含循环 ⇒ 整臂静默丢失），那条臂**根本没执行**，0.42s 是空跑，不能用作「全局按名寻址」的耗时基线。mode=2（函数内局部循环 1.66s）与 mode=3（数组写循环 2.56s）不受该缺陷影响，仍是 H1/H2 的有效对照。**副作用**：H1 若要拿「同一循环体 全局 vs 局部」的干净差值，必须等 CODEGEN-006 修复后复测，或改用函数内 `global $g;` 形状取全局读写面（待复测确认其自身是否也受 006 家族影响）。

### 3.1 上条更正的兑现：mode=1 有效读数回填（2026-10-04 实测，CODEGEN-006 **A 批落地后**）

A 批（四处臂尾 `.br` 的窄循环头派发）落地并重建二进制后复测同一探针、同一档位（`--optimize=release-fast --no-debug-info`，`n=30_000_000`，`/usr/bin/time -p`）：

| mode | 形状 | AOT 本次 | AOT 旧读 | PHP 真值 | 输出等值 |
|---|---|---|---|---|---|
| 1 | 顶层全局循环（`$g/$h/$i` 为全局） | **6.57s** | 0.42s（空跑，作废） | 0.28s | `M1 g=449999985000000 h=90000000` **逐字节等值** |
| 2 | 函数内局部循环（循环体与 mode=1 逐字同构） | 1.59s | 1.66s | 0.20s | `M2 g=449999985000000 h=90000000` 等值 |
| 3 | 数组写循环 | 2.46s | 2.56s | **无可比真值**（PHP 在 `n=30M` 触 128M 内存上限 Fatal，属 PHP 侧限制，非 AOT 缺陷） | `M3 sum=450000015000000`（仅 AOT 侧计时） |

⇒ **H1 首次拿到可分离的净成本**：mode=1 − mode=2 = **4.98s / 30M 迭代 ≈ 166 ns/迭代**，即「同一循环体仅把局部槽换成全局按名寻址」的代价（每迭代 3 读 + 2 写 ⇒ 折单条约 33 ns，与 §3 H1 行「5 ns vs 150 ns 量级差」的怀疑方向一致，且落在其上界）。mode=2/mode=3 与旧读数的差（1.59 vs 1.66、2.46 vs 2.56）在单次量测噪声内，**说明 A 批没有改变函数内/数组路径的性能**，收益只体现在 mode=1 由「不执行」变为「执行且正确」。

⇒ §3 H1 行的「首要嫌疑」自本起由**代码证据升级为运行期实测**，`§4` P0「H1 全局变量去虚化」的预期收益可据此定量：顶层脚本体若全部去虚化，理论上界为 **6.57s → 1.59s（4.1×）**；未做该改造前，任何「AOT 比 PHP 慢 20×」的语料级归因都应先扣除这 166 ns/迭代的全局寻址底噪。

⇒ **§6 的连带更正**：CODEGEN-006 工单 §6 把本探针 mode=1 判为「限期作废」，本次即其到期复测，判定改为**已回填有效**（见该工单 §6）。

---

## 4. 后续方案（优先级 × 影响面 × 落地成本）

| 优先级 | 方案 | 影响面 | 落地成本 / 实测依据 |
|---|---|---|---|
| **P0（待裁决）** | **把 `native_linker.zig:32446` 逃逸门阈值从 200KB 下调**（如 32KB），使小脚本也升 `-OReleaseFast` | 只改 `zig build-exe` 的 `-O`（IR pass 集**不受影响**，`compiler.zig:637-645` 的 `strip_symbols` 判定也不受影响）⇒ **不改生成码** ⇒ 冻结基线哈希的是 `main.zig`，**零漂移、不需重冻结**（与「改默认值」路线不等价，见下一行）。**但收益面在语料上为 0**：任务 #94 实测语料最小 `main.zig` = `f040_flyweight_forest_pool` **278,560 bytes** ⇒ 门限对 68 语料**已 100% 命中**，下调只对 `<200KB` 的脚本（最小探针/嵌入式产物）生效 | 一行改动。**收益实测 2.65×～3.44×**（该收益属 `-O` 轴，§2.1 同生成码实测）。必须跑官方 68 回归 + 四道探针门确认无行为变化（ReleaseFast 下未定义行为可能显形） |
| **P0（实测否决，建议降级为 P2）** | ~~**默认档位 `release_small` → `release_fast`**（`src/aot/compiler.zig:140`）~~ —— 与上一行**不等价**：`--optimize` 同时驱动 IR pass 集（`compiler.zig:247` → `optimizer.zig:60`）与 zig `-O` | ~~只改 `-O` 与 `strip_symbols` ⇒ **不改生成码** ⇒ **理论上零漂移、不需重冻结~~ ⇒ **已被任务 #88/#94 实测否证**：同脚本两档 `main.zig` md5/行数不同；**68 语料实测 67/67 生成码漂移（须整体重冻结）+ 19/67 红**（17 静默错值 + 2 运行失败），收益仅生成码行数 −1.27%（−29,041/2,292,895），代价另有产物体积 +39%～42%、编译墙钟 +78%（实测） | 一行改动但**当前不具备落地条件**：抬档代价 100% 落在 5 枚 CLI 可达旋钮（#95 双向夹逼，8 枚不可达字段语料发射中性），其中 **18/19 枚红形由 `licm` 家族引发**（`licm` 单枚 7 红、`licm`+`max_iterations=5` 放大到 18 红，typespec 零贡献），**与内联无关**（仅 `f152` 属 CODEGEN-007）⇒ 单解 CODEGEN-007 只能转 1 枚。**#96 已把机制取证到行**：根因不是 LICM 的提升，而是 `optimizer.zig` 的 **cfg_cleanup 把被搬空的条件臂当 trampoline 删除**（`tryRemoveTrampolineBlock` `:4318-4340` → phi 入边原地改同源 → `then==else` 折叠）⇒ `??`／三元选择语义整体消失；**#97 只读金丝雀面扫量化本链解释力 = 9/19 签名面**（「LICM 单枚红」组 7/7）。**#98 再进一格为旗标因果面**：`cfg_cleanup` 自带 CLI 开关（`main.zig:165-168` → `compiler.zig:673` → `optimizer.zig:736`），抬档臂上**只关掉它、LICM 仍开** ⇒ `DISCRIM_DONE total=19 pass=10 diff=5 runtime_fail=2 compile_fail=2`，**因果面 10/19 > 签名面 9/19**（转绿的 10 枚里 6 枚 C1 完全不可见）⇒ R2 承重性由「双臂推断」升级为**旗标因果实证**，未解释面按此收窄为 **9 枚**。**同时实测否决「抬档顺手关 `cfg_cleanup`」这条旁路**：`f124`/`f134` 在该臂报 `Zig code generation failed: AstDirectGenerationFailed`，且**默认档、默认档+licm 两臂同样失败** ⇒ 发射侧对 cfg_cleanup 是**档位无关的硬依赖**，关它既留红又砸编译。主修判据已登记于 [AOT-OPT-001](AOT-OPT-001-licm-multi-iteration-silent-wrong-values.md) §5.2/§5.5/§6/§7，**门控待老铁点头**，故本行仍是「一行改动但当前不具备落地条件」 |
| **P0（新立项）** | **H1 全局变量去虚化**：发射期把「静态可证明不被 `=&`/`$$var`/`extract`/`global` 引用、且不属超全局」的顶层变量降级为**函数局部槽位**（一次解析、下标访问），`setGlobalVar` 的引用链解析与 `findAllRefsToSource` 扫描对这类变量整体跳过 | 触 `native_linker` 的变量读写发射 + 生命周期分析；正确性风险集中在「别名/引用」判定，判错即语义错 ⇒ 必须保守白名单 | 中～大；须先做全量影子实测（承接 CODEGEN-005 process rule (a)：实现字面等于实测口径）。**这是 §2.2 那 20–29× 的首要嫌疑** |
| **P1** | **H2 标量特化**：IR 类型已带 `.i64`，为「全链 i64 且无引用」的表达式发未装箱整型快路（`php_add` → `+`，边界/溢出再回落到 `Value`） | 与 H1 同域；可后置，H1 收益到手后再评估剩余差距 | 大；需新增类型窄化的可证明性判据 |
| **P1** | **H3 源码位置发射收敛**：仅在可抛错指令处发 `setSourceLocation`，同源码行的连续指令合并为一次 | 影响**错误/警告输出的行号定位**。§七-5 已声明 AOT 栈行号不计入测试失败 ⇒ 但 Deprecated 警告文案仍依赖它，属**可观测性换性能**的取舍，须用户点头 | 小（三处发射点加门控） |
| **P2** | **解禁函数级否决位**（`has_do_while` 等，`:17482` 置位、`:17521`/`:17566` 否决） | 实测运行期代价只有 +2%～+4.7%（§2.3）⇒ 性能理由不成立；真正的动机是**语义/覆盖面**（`generateDoWhileFromLabels` 现为不可达死代码）。解禁必须与 CODEGEN-005 行 16 的「第三站点按方案 R 补齐」**同批**，否则站点③ 以原始缺陷形态生效 | 大（含 IR 前置块缺失问题）；低优先 |

---

## 5. 复跑路径

```bash
cd /Users/wangjianjun/products/parser            # --compile 必须在仓库根（copyRuntimeLib 按 cwd 解析）
# 默认档（= release_small，因生成码 < 200KB）
timeout 300 ./zig-out/bin/php-interpreter --compile --no-debug-info --output=/tmp/aot_b /tmp/bench_num_tmp.php
timeout 30 /tmp/aot_b > /dev/null
# 对照档
timeout 300 ./zig-out/bin/php-interpreter --compile --no-debug-info --optimize=release-fast --output=/tmp/aot_bf /tmp/bench_num_tmp.php
timeout 30 /tmp/aot_bf > /dev/null
# 真值
timeout 30 /opt/homebrew/bin/php /tmp/bench_num_tmp.php
```

档位改动后的验收：**官方 68 回归**（`scripts/regression_test_720.sh`，判据 PASS 67 / SKIP 1 / FAIL_* = 0）+ **四道探针门**（17 形等值门、RC-4 诊断门、RC-5 八形 + 三单形、新 `c005_dowhile_probe_run_tmp.sh`）+ `timeout 240 zig build test`。~~冻结基线漂移门可复跑确认「档位不改生成码」（预期 `diff=0`）~~ ⇒ **预期已按实测更正（任务 #94）**：只有**阈值路线**预期 `diff=0`；**改默认值路线**预期 `DRIFT_DONE diff=67`（实测 67/67 漂移），且须额外跑 A/B/C 三臂面判据（`c007_releasefast_face_tmp.sh`／`c007_rf_control_tmp.sh`／`c007_inline_only_face_tmp.sh`，见 CODEGEN-007 §6.1）。

---

## 6. 风险与诚实边界

- **不是回归，是基线**：§2 的所有慢都是**先于本工单存在**的实现特征，本轮 facet-1/facet-2 落地未引入也未修复任何一条。
- **bench 代表面有限**：四条 bench 是标量/数组热环，**不等于**语料 68 脚本的真实分布；结论只用于「档位与热点是否存在、量级多大」，不用于承诺语料级加速比。
- **H1/H2/H3 尚未做单变量量测**：热点归属来自生成码逐字摘录与调用计数，**百分比归因是待测项**，禁止在后续文档里反述为「已量化」。
- **档位改动的隐藏风险**：ReleaseFast 关闭了 Zig 的运行时安全检查（溢出/越界/无效整数），若现存代码有未暴露的 UB，改档位可能**把它变成崩溃或错值**。⇒ 这正是必须先跑全门、不得只跑探针的理由。
- **`strip_symbols` 连带变化**：`compiler.zig:645` 仅在 `release_small` 时 strip ⇒ 改默认档会同时改变符号表状态（体积 +40% 的另一半来源）。AOT 栈行号差异按 §七-5 不计入失败。

## 7. 待裁决（§六 确认机制）

| # | 决策 | 我的建议 |
|---|---|---|
| 1 | 是否把默认 `optimize_level` 改为 `release_fast`（或把 `:32446` 阈值下调到 32KB）？ | **建议只改阈值**（不动「默认」语义、零生成码漂移）；**改默认值一项已按任务 #94 实测撤回** —— 68 语料实测 67/67 漂移 + 19/67 红（17 静默错值 + 2 运行失败），收益只有生成码行数 −1.27%，且无运行时基准 ⇒ 须先逐 pass 归因再重议。阈值路线的剩余收益也**不在语料内**（门限已对 68 语料 100% 命中），只覆盖 `<200KB` 脚本。**（#95 更新）归因已完成**：19 枚红里 **18 枚属 LICM 家族**（新立 [AOT-OPT-001](AOT-OPT-001-licm-multi-iteration-silent-wrong-values.md)：`licm` 单枚 7 红、`licm+max_iterations=5` 18 红、typespec 零贡献），**内联只 1 枚**（`f152`，CODEGEN-007）⇒ 抬档的真实前置是 OPT-001 而非 007；且该红面**在默认档加两枚旗标即可 100% 复现**（`--aot-enable-pass=licm --aot-max-iterations=5`），取证不必再抬整档。**（#96/#97 更新）机制已取证到行、解释力已量化**：根因**不在 LICM 的提升**，而在 `optimizer.zig` 的 **cfg_cleanup**（被搬空的条件臂遭 `tryRemoveTrampolineBlock` 删除 → phi 双入边改同一前驱 → `then==else` 折叠 ⇒ 选择语义消失 ⇒ 静默错值），默认档因 `:4319`「块非空即拒删」而**从未触发**；只读金丝雀面扫 19 枚 × 双臂读出 **本链解释 9/19**（LICM 单枚红组 7/7 全覆盖）⇒ **余下 10 枚必另有机制**（该口径已由 **#98** 按因果分组收窄为 **9 枚**，见下），且取证通道已实测为 `--no-link --emit-ir/--dump-zig-path`（生成码与完整链接逐字节等价，单形成本分钟级 → **秒级**）。**（#98 追加因果口径与一条否证）**：因 `cfg_cleanup` 自带 CLI 开关，抬档臂上单独关掉它（LICM 仍开）⇒ **因果面 10/19**（> C1 签名面 9/19，转绿者有 6 枚为 C1 不可见）⇒ 本链的承重性从推断升级为**旗标因果实证**；同轮**实测否决**「抬档顺手关 `cfg_cleanup`」这条捷径（`f124`/`f134` `AstDirectGenerationFailed`，默认档与默认档+licm 同样失败 ⇒ 发射侧对 cfg_cleanup 是**档位无关的硬依赖**），故今后任何「抬档时顺手关掉某个整理型 pass」的提案都必须先过这道具象化闸门。OPT-001 §6 的 **P0 主修（收紧 R2 删块判据）+ 发射侧「phi 同源异值」诊断**已登记验收硬门，**仍属门控项、未动一行源码**。**（#101 追加：迭代维已定价完毕，且是「开关」不是「刻度」）**逐轮曲线（OPT-001 §5.8）实测 = **签名面 9→17、输出面 7→18，两面都在迭代 2 台阶到顶**（`r2`/`r3`/`r4`/`r5` 命中集合与三枚计数相同；`r4` 与 #100 `li5` 的判定 + `main.zig` 行数/md5 **19/19 全等** ⇒ 轮 4 与轮 5 产出逐字节相同的生成码）⇒ 「抬到 3」与「抬到 5」的红面代价**相同**，风险只由「是否 ≥2」这**一个开关**决定；`r2` 与 `r3+` 仅在 4 枚形上**幅值**不同（判定不变）。同时 **#101 实测更正默认档 = `.release_small` ⇒ `max_iterations` 实为 1**（`compiler.zig:140` → `optimizer.zig:219`；`optimizer.zig:103` 的 `= 3` 被四份具名预设全覆盖）⇒ 本工单此前「1→5」「3→5」两种措辞一律按 **1 轮基线**重读，**当前零红面基线正是靠这个 1 轮维持**；但同一饱和点意味着 **`release_safe`（`optimizer.zig:157` `licm=true`、`:163` `max_iterations=3`）也落在引爆区**，「只测 release-fast」不再构成对中间档的免检依据（该档面扫**未做**，登记为遗留 ⇒ **#102 已实测销账**：`--optimize=release-safe` 在全部 68 语料上双臂面扫 = 非绿 **18/67**，红形名单与饱和档 `li5` 的 18 枚**逐枚全等**，且相对「默认档 + 4 枚 CLI 旗标」**67/67 逐字节同生成码** ⇒ 中间档**不是**安全落点，读数见 OPT-001 §5.9.1）。⇒ **本裁决项维持「建议只改阈值」不变，并且「换一档」分支（在默认档与 `release-fast` 之间另寻中间档）经 #102 实测正式关闭** —— 三档非绿面实测 = 默认档 **0**／`release-safe` **18**／`release-fast` **19**，中间档红面与饱和面同形同数 ⇒ 抬档议题只剩「先修 OPT-001 §6 P0 再抬」 |
| 2 | 是否立 H1（全局变量去虚化）为下一个主攻批次？ | 建议先做 **H1 的影子实测轮**（只读 + 非行为插桩，统计「可安全降槽」的变量占比），拿到占比再决定是否动发射 |
| 3 | H3（源码位置收敛）用可观测性换性能，是否接受？ | 建议**押后**，等 H1/H2 到手后仍不达标再谈 |

本轮**未改任何代码**，也未改 `compiler.zig` 的默认值。

## 8. 锚点代次刷新（2026-10-04，D 批代次 `9490bf9f` 实测；只读复核，零代码改动）

> **背景**：CODEGEN-006 的 A + D 两批在 `src/aot/native_linker.zig` 前部插入代码，使本文与其余工单里记在 RC-5 代次 `3ae7b34e` 上的 `native_linker.zig` 行号整体漂移（流程规约 (b)：锚点必须带代次戳并在行动前 re-grep）。本节给出**分段偏移表**与**七个独立实测校验点**，避免未来任何一轮按失效行号定位。
>
> **适用边界**：下表**只对记在 `3ae7b34e`（RC-5 工作区代次）上的锚点成立**，本文 §3/§4/§7 引用的 `native_linker.zig` 行号经逐一复核**全部**属该代次（故 +117 全部命中）。**跨代次偏移不可连加推算** ⇒ 反例实证见 [AOT-REF-003 §11.2](AOT-REF-003-byref-iteration-liveset-and-iterator-relocation-crash.md)：那条 builtin 表锚点实际偏移是 **+126**（记在更早的 RC-4 `0ff09cf` 树上）。凡要动手的锚点仍必须按**符号** grep 实测。

### 8.1 分段偏移表（`3ae7b34e` → `9490bf9f`，7 个 hunk 的实测结果）

| 旧行号区间（`3ae7b34e`） | 偏移 | 插入内容 |
|---|---|---|
| ≤ `:981` | **+0** | 无任何插入发生在其之前 |
| `:982`–`:9058` | **+91** | A 批 `dispatchArmTailBrIntoLoop` + D 批 `emitChainUnwindArmPair`（新 `:983`–`:1073`） |
| `:9059`–`:9099` | **+95** | ＋ A 站点 then（`br_t0`，新 `:9150`–`:9154`） |
| `:9100`–`:9142` | **+99** | ＋ A 站点 else（`br_t`，新 `:9195`–`:9199`） |
| `:9143`–`:10012` | **+104** | ＋ D 站点①（新 `:9242`–`:9247`） |
| `:10013`–`:10052` | **+108** | ＋ A 孪生 then（`br_t0b`，新 `:10117`–`:10121`） |
| `:10053`–`:10095` | **+112** | ＋ A 孪生 else（新 `:10161`–`:10165`） |
| ≥ `:10096` | **+117** | ＋ D 孪生站点②（新 `:10208`–`:10213`）⇒ **绝大多数工单锚点落在此段** |

合计 `+117` = 行数实测 32546 → 32663 ✓。

### 8.2 七个偏移表校验点 + 1 个反例（全部为当前树 grep 实测，非推算）

| 符号 / 语句 | 旧锚点 | 新锚点（实测） | 段 |
|---|---|---|---|
| `if (zig_code.len > 200_000 …== .release_small)` | `:32195` | **`:32312`** | +117 ✓ |
| `runtime.setSourceLocation` 三热点 | `:19436` / `:20524` / `:22921` | **`:19553` / `:20641` / `:23038`** | +117 ✓ |
| `has_do_while` 声明 / 置位 | `:17474` / `:17482` | **`:17591` / `:17599`** | +117 ✓ |
| 否决位两处（AST 直发 / 结构化） | `:17521` / `:17566` | **`:17638` / `:17683`** | +117 ✓ |
| RC-5 站点②（for 外层 latch 交还） | `:14711`–`:14721` | **`:14828`–`:14838`** | +117 ✓ |
| RC-5 站点①（while 乱序出口交还） | `:16299`–`:16303` | **`:16416`–`:16420`** | +117 ✓ |
| `isOuterLoopLatch` / `findExitEdgeSourceIdx` | `:951` / `:959` | **`:951` / `:959`（未变）** | +0 ✓ |
| `copyRuntimeLib`（AOT 取运行时模板） | 无（他单记 `:32219`，属更早代次） | **`fn copyRuntimeLib` `:32378`，模板路径数组 `:32393`**（全文件唯一命中） | 只能实测 |

**§8.2.1 当代次复验（2026-10-06，任务 #94，代次 `fbe6382a`/32797）**：本次只复验了档位相关的那一枚锚点，上表其余七行**未重测**（属下一轮巡检面）。`grep -n "200_000" src/aot/native_linker.zig` 实测**唯一命中 `:32446`** ⇒ 与本工单末表（`ReleaseFast 逃逸门 | :32445 | :32446`）**一致**，上表的 `:32312`（D 批代次 32663 行）已作废为历史读数；文中所有「200KB 逃逸门」引用一律以 **`:32445-32446`** 为准（`:32445` = 注释行「大型代码使用 ReleaseFast 避免 ReleaseSmall 编译超时」）。

### 8.3 本文其余锚点的处置

| 锚点 | 所属文件 | 判定 |
|---|---|---|
| `src/aot/compiler.zig:140`（默认档） | `compiler.zig` | **仍有效**：该文件本轮 `git status` 干净 ⇒ 零改动 |
| `runtime_lib_template.zig:340`（`setSourceLocation` 实现） | 模板 | **仍有效**：md5 保持 `008b7b639f1069cb73e443064e115ed1` |
| 生成码里的 12 次/迭代调用计数、字节数、耗时读数 | 产物 | 与行号无关，读数为历史实测，无需刷新 |

### 8.4 代次再刷新（2026-10-05，R9-B 代次 `0e38b018`／32796 行实测；只读，零代码改动）

§8.2 的「新锚点」列属 **D 批代次 `9490bf9f`**，已被 R9-B（IPD helper +117 行插在 `:1073`–`:1189`、B 站点内联块 +16 行插在 `:10180`–`:10196`）整体推翻 ⇒ 该表所有 `≥ :10096` 的锚点再 **+133**。下表为**当前工作区**的符号／字面量 grep 实测值（非偏移推算），动手时以本表为准。

| 符号 / 语句 | `9490bf9f`（§8.2） | **当前树实测（`0e38b018`）** | 实测依据 |
|---|---|---|---|
| ReleaseFast 逃逸门 `zig_code.len > 200_000` | `:32312` | **`:32445`** | `grep -n 200_000` 唯一命中 |
| `runtime.setSourceLocation` 三热点 | `:19553`/`:20641`/`:23038` | **`:19686` / `:20774` / `:23171`** | `grep -n "runtime.setSourceLocation"` = 5 处（另有状态机侧 `:19279`/`:31998`） |
| `has_do_while` 声明 / 置位 | `:17591`/`:17599` | **`:17724–:17729`（五枚否决位声明）** / **`:17732`（置位）** | `grep -n has_do_while` |
| 函数级回退门（AST 直发 / 结构化） | `:17638`/`:17683` | 门 **`:17771`** ⇒ 调用 `tryGenerateFromLabels` **`:17775`**；门 **`:17816`** ⇒ 调用 `tryGenerateStructuredControlFlowNew` **`:17824`**（`:17825` 为其后的 `if (structured_result)`；本行原记 `:17825`，2026-10-05 按 `grep -n` 复测更正） | `grep -n` 复测：`if (!func.has_multi_level_break and !has_do_while …)` 在 `:17771`/`:17816`，两枚调用行 `:17775`/`:17824` |
| RC-5 站点②（**`generateForFromLabels`** 外层 latch 交还，fn 在 `:13268`） | `:14828–:14838` | **`:14961–:14971`**（`if (self.in_cond_br_branch)` ⇒ `processed.remove(exit_idx)` ⇒ `last_loop_fallthrough_idx = exit_idx`（`:14963`）⇒ `return exit_idx`） | `grep -n "last_loop_fallthrough_idx = exit_idx"` = `:14925`/`:14963`/`:16550` 三处，按 fn 边界归属 |
| RC-5 站点①（**`generateWhileFromLabels`** 乱序出口交还，fn 在 `:15034`） | `:16416–:16420` | **`:16549–:16553`**（`if (isOuterLoopLatch(shared_merge_blk.label) and self.in_cond_br_branch)` ⇒ `= exit_idx`（`:16550`）⇒ `return exit_idx`） | 同上 |
| `isOuterLoopLatch` / `findExitEdgeSourceIdx` | `:951` / `:959` | **`:951` / `:959`（未变，插在 helper 插入点之前）** | `grep -n "fn isOuterLoopLatch\|fn findExitEdgeSourceIdx"` |
| `copyRuntimeLib` / 模板路径 join | `:32378` / `:32393` | **`:32511`** / **`:32526`**（字面量 `"src/aot/runtime_lib_template.zig"`） | `grep -n "fn copyRuntimeLib"` |

**模板路径更正（本节实测）**：模板文件实际在 **`src/aot/runtime_lib_template.zig`**（`find` 全仓唯一命中），**不是** `src/runtime/`；链接器内的加载路径字面量亦写作 `src/aot/runtime_lib_template.zig` ⇒ §8.3 与 §4 H3 行的 `runtime_lib_template.zig:340` 指同一文件，路径此前未写目录、现补齐。该文件与 `src/aot/compiler.zig` 均 `git status --porcelain` **干净** ⇒ 默认档锚点 `compiler.zig:140`（`optimize_level: OptimizeLevel = .release_small`）与模板 `:340`（`pub fn setSourceLocation`）**逐字仍有效**。

### 8.5 代次再刷新（2026-10-05，当前工作区代次 `fbe6382a`／32797 行实测；只读巡检，零代码改动）

#74 纯注释批在 `:15620`–`:15621` 处把 **2 行注释替换为 3 行**（`git diff -U0` = `@@ -15620,2 +15620,3 @@` + `@@ -25597,2 +25598,2 @@`；`git diff -U2` 逐行实读为 `@@ -15618,6 +15618,7 @@` + `@@ -25595,6 +25596,6 @@`），故 §8.4 表中 **旧行号 ≥ `:15622` 的锚点一律 +1**，`≤ :15619` 者不变（`:15620`/`:15621` 这两个旧行号在新代次指向别的文字，禁止直接引用）。该规则本轮**逐条按符号 grep 复测**（非推算）后成立，实例：`fn markReachableRestBlocks` 定义 `:25604` → **`:25605`**、doc 注释起行旧 `:25595` → 新 `**:25596**`：

| 符号 / 语句 | §8.4（`0e38b018`） | **当前树实测（`fbe6382a`）** | 实测依据（该行内容） |
|---|---|---|---|
| `runtime.setSourceLocation` 三热点 | `:19686`/`:20774`/`:23171` | **`:19687` / `:20775` / `:23172`** | `grep -n "runtime.setSourceLocation(\"{s}\", {d});"` 逐行命中，三行均为 `inst.location.file/line` 版式 |
| 状态机侧两处（同族发射） | `:19279`/`:31998` | **`:19280` / `:31999`** | 同 grep 的其余两枚命中，版式为 `case.source_line` |
| ReleaseFast 逃逸门 | `:32445` | **`:32446`** | `if (zig_code.len > 200_000 and self.config.optimize_level == .release_small)`；`grep -n 200_000` 唯一命中 |
| 函数级否决位声明 | `:17724–:17729`（写为「五枚」） | **`:17725–:17730`，实为六枚** | 逐行 = `has_do_while`/`has_switch`/`has_match`/`has_recursive_call`/`has_foreach`/`has_exception_handler` ⇒ **§8.4 的「五枚」漏记了 `has_foreach`**，本轮更正计数与名单 |
| 置位循环 | `:17732` | **`:17732`（`for (func.blocks.items)`）⇒ 首枚置位在 `:17733`** | `:17733` = `if (... "do_while" ...) has_do_while = true;` |
| AST-direct 门 / 调用 | `:17771` / `:17775` | **`:17772` / `:17776`** | `:17772` = `if (!func.has_multi_level_break and !has_do_while and ... and !has_exception_handler) {`（**注意此门条件不含 `has_recursive_call`**），`:17776` = `try self.tryGenerateFromLabels(...)` |
| 结构化门 / 调用 | `:17816` / `:17824`（正文另记 `:17825`） | **`:17817` / `:17825`** | `:17817` 条件含 `!has_recursive_call`，`:17825` = `const structured_result = try self.tryGenerateStructuredControlFlowNew(...)` |
| `copyRuntimeLib` / 模板路径 join | `:32511` / `:32526` | **`:32512` / `:32527`** | `grep -n "fn copyRuntimeLib"` / 字面量唯一命中 |
| RC-5 站点② / `generateForFromLabels` 函数头 | `:14961–:14971` / `:13268` | **未变（`< :15620`）** | 复测：`:14961` = `if (self.in_cond_br_branch) {`，`:14963` = `last_loop_fallthrough_idx = exit_idx`；`grep -n "fn generateForFromLabels"` = `:13268` |
| RC-5 站点① | `:16549–:16553` | **`:16550–:16554`** | `:16550` = `if (isOuterLoopLatch(shared_merge_blk.label) and self.in_cond_br_branch) {` ⇒ `:16553` `return exit_idx;` |
| `generateWhileFromLabels` 函数头 | `:15034` | **未变** | `grep -n "fn generateWhileFromLabels"` = `:15034`（在 `:15620` 之前） |

**§4 H3 行的处置**：该行内的 `native_linker.zig:19436`、`:20524`、`:22921` 是 **RC-4 代次**读数，已被 §8.4 与本轮两次刷新覆盖 ⇒ 以本表 `:19687 / :20775 / :23172` 为准；H3 的机制判断（每指令 `setSourceLocation` 是热点、可按档关闭）与三处发射点的**版式**均复验不变。

**状态判定维持**：默认档 `compiler.zig:140`、模板 `:340` 逐字有效，两文件最后提交分别为 `567b05f`（2026-07-24）与 `b21cdfd`（2026-09-30）且工作区干净 ⇒ §7 的三项裁决内容未因行号漂移改变，仍待老铁裁决。

---

**更新日志（档位路线相关，2026-10-06，任务 #94）**：
- **§4 的 P0 行已按实测拆成两行**（阈值下调 / 改默认值），**§7 裁决项 1 的建议已按实测收窄为「只改阈值」**，**§5 的「预期 `diff=0`」加了限定**（只对阈值路线成立）。
- 决定性读数（68 语料，三臂只读实测，harness 永久登记于 `fuzzy_scripts_720/tmp/c007_{releasefast_face,rf_control,inline_only_face}_tmp.sh`）：`--optimize=release-fast` ⇒ **67/67 生成码漂移**（`gen_same=0`，须整体重冻结）、**17 枚静默错值 + 2 枚运行失败**（`f152` SIGSEGV／`f160` exit=255）、0 编译失败；这 19 枚红形在**默认档 19/19 全绿**；「只开内联 + threshold 50」单变量臂 ⇒ **66/67 生成码与冻结基线逐字节相同**，只点亮 `f152` 一枚 ⇒ **抬档代价的 18/19 与内联无关**，本工单不能把「先解 CODEGEN-007」当作抬档的唯一前置。
- **收益边界**：语料最小 `main.zig` = `f040_flyweight_forest_pool` **278,560 bytes**（实测打印 `-OReleaseFast`）⇒ 逃逸门对 68 语料**已 100% 命中**，阈值下调路线在语料内剩余收益 **0**；§2.1 的 2.65×～3.44× 收益只适用于 `<200KB` 的产物。抬默认档一侧的实测收益仅为生成码行数 **−1.27%**（2,292,895 → 2,263,854），**无运行时基准**。
- **静态捷径否证**：`main.zig` 行数差**不能**预测红/绿（逐脚本差值实测：48 枚绿形中 **38 枚**的收缩幅度大于最小红形 `f025` 的 17 行，绿形最大收缩 1,470 行 `f097`；19 枚红形差值横跨 −409（`f152` 增长）到 +2,854（`f117` 收缩））⇒ 抬档验收只能逐脚本跑比对。
- **归因轮的通道约束（实读 `src/main.zig:124-172` + `compiler.zig:662-679`）**：两档 13 枚差异字段中**只有 5 枚**可由 CLI 关闭（`inline`／`typespec`／`licm`／`max_iterations`／`inline_threshold`），另 8 枚（`copy_propagation`／`max_instructions_per_function`／`scalar_replacement`／`gvn`／`advanced_sccp`／`slp_vectorization`／`polyhedral_optimization`／`loop_vectorization`）**无开关** ⇒ 「把 18 枚红形钉到单枚 pass」只能覆盖 5/13 维，5 枚全关仍红的红形必然要求改 `optimizer.zig`（门控项，需老铁点头）。
- 零源码改动（`native_linker.zig` 仍为 `fbe6382a`/32797 的 #74 纯注释批 numstat `5 4`；`optimizer.zig` `252234ef`/6877、`compiler.zig`、`runtime_lib_template.zig` 均未改；二进制 `1f15e4ce9b5c9cdaaef7cabf5efb9c76` 冻结）。**§7 三项裁决仍全部待老铁点头。**

---

**更新日志（归因与取证，2026-10-06，任务 #95/#96/#97）**：
- **#95 关闭上条「归因轮的通道约束」死角**（无需改 `optimizer.zig`）：E 臂（release-fast − 5 枚可达旋钮）`KNOCKOUT_DONE total=68 gen_same=67 gen_drift=0 pass=67 diff=0` ⇄ all5 臂（默认档 + 5 枚全开）19 枚红形生成码 md5 与整档 release-fast **19/19 逐枚相同** ⇒ 双向夹逼证明**另 8 枚不可达字段在 68 语料上发射中性、语义无影响**，抬档代价 100% 落在 5 枚 CLI 可达旋钮；九臂矩阵读数：`typespec` 13 漂移/**0 红**、`iter5` 15/**0**、`ti` 18/**0**、`licm` 19/**7**、`li5` 19/**18**、`trip` 19/**18**（红集与 `li5` 逐枚相同 ⇒ typespec 零贡献）、`all5` 19/**19** ⇒ **LICM 是红面必要条件**。
- **#96 机制取证到行**（`f016` 双臂 KEEP_TEMP + `--emit-ir` 只读 diff）：**否证「LICM 提错」**，根因链在 `optimizer.zig` cfg_cleanup —— 被搬空的条件臂遭 `tryRemoveTrampolineBlock` `:4318-4340` 当 trampoline 删除（R2，`:4319`「块非空即拒删」正是**默认档永不触发**的原因）→ `expandPhiIncomingForRemovedBlock` `:4415-4472`（区间末行原记 `:4460`，由 **#98 逐符号复测更正**）把 phi 双入边原地改成同一前驱（R3）→ `simplifyTrivialConditionalBranches` `:4296-4308` 见 `then==else` 折掉条件（R4）→ 发射侧对同源双值 phi 不发臂拷贝、交汇寄存器停 `initNull()`（R5）⇒ `??` 选择语义整体消失 ⇒ `{"ServerA":8}`→`{"ServerA":1}`。**同时作废 #95 登记的 H1–H5 假设清单。**
- **#97 解释力量化 + 取证成本降低**：两枚只读金丝雀（C1=优化后 IR「同源异值 phi」／C2=生成码「声明未赋值 `reg_N`」）× 19 枚红形 × 双臂 ⇒ `CANARY_SWEEP_DONE total=19 chain_hit=9 no_hit=10 compile_fail=0`，即**本链只解释 9/19**（LICM 单枚红组 7/7），**余下 10 枚必另有机制**（⚠ #99 改口：其中 5 枚仍错值形实测为**同一条链的不同发射结局**，见本工单文末 #99 条与 OPT-001 §5.6）⇒ 本工单**不得**把「解 OPT-001 一条链」写成抬档的唯一前置。通道等价性实测：`--no-link --dump-zig-path` 产物与完整链接 `main.zig` 逐字节相同 ⇒ 单形取证成本从分钟级降到**秒级**（C2 有底噪，判据须取双臂 delta）。
- **#94 的四条 harness 之外新增 2 枚永久资产**（`opt001_f016_dualarm_tmp.sh`／`opt001_canary_sweep_tmp.sh` + TSV，登记于 OPT-001 §7）。三轮累计**零源码改动**（`optimizer.zig` `252234ef`/6877 无 `git diff`、二进制 `1f15e4ce9b5c9cdaaef7cabf5efb9c76` 未重建）；OPT-001 §6 的 P0 主修与发射侧诊断**仍为门控项，未动一行**。

---

**更新日志（因果判别，2026-10-06，任务 #98）**：
- **开工前置 = 锚点逐符号复测**（`optimizer.zig` 代次 `252234ef`／6877 行，`git status` 干净）：OPT-001 §5.2/§2 的全部锚点**逐字命中、零漂移**，唯一更正为 R3 函数区间末行 `:4415-4460` → `:4415-4472`（已同步本工单 #96 那条）。本轮同时否证了自己开工前的一次「漂移」误报，成因是行号打印脚本的 `awk` 偏移。
- **实读到一枚此前未登记的旋钮**：`cfg_cleanup` **不是**两档 13 枚差异字段之一（`releaseFast()` `:189` 与 `releaseSmall()` `:217` 皆为 `true`），但**自带 CLI 开关**（`main.zig:165-168`，名 `cfg-cleanup`/`cfg` → `compiler.zig:673` → `optimizer.zig:736` 门）⇒ 与 §2/#94 的「5/13 可达」口径**不冲突**（它不在差异集里），并给抬档红面提供了一个**零代码改动**的因果判别通道（OPT-001 记为 C3）。
- **判别臂读数**：19 枚红形 × 单一变量 `--optimize=release-fast --aot-disable-pass=cfg-cleanup`（控制组 = 同代次 A 臂）⇒ `DISCRIM_DONE total=19 pass=10 diff=5 runtime_fail=2 compile_fail=2`；分组 `CHAIN: PASS=4 DIFF=2 RUNTIME_FAIL=1 COMPILE_FAIL=2` ⇄ `NOHIT: PASS=6 DIFF=3 RUNTIME_FAIL=1 COMPILE_FAIL=0`。
- **三条结论**：**①R2 因果成立**（LICM 仍开、只关 cfg_cleanup ⇒ `f016` 输出与 PHP 真值 `diff` 为空）；**②C1 是下界探针不是判据**（10 枚转绿里 6 枚 C1 delta=0 ⇒ 因果面 10/19 > 签名面 9/19，未解释面由 10 枚收窄为 **9 枚**）；**③「抬档顺手关 cfg_cleanup」这条旁路实测否决**（`f124`/`f134` 报 `AstDirectGenerationFailed`，且默认档、默认档+licm 两臂同样失败 ⇒ 发射侧对 cfg_cleanup 是**档位无关的硬依赖**，本单主修只能走判据收紧）。阴性对照成立：`f152` 仍 `exit=139`（内联缺陷，旗标不该救它）；`f177` 本臂 `exit=124`（`timeout 10` 判停，登记为 `TIMEOUT_10S`，挂起/过慢未区分）。
- **harness 口径两处自我更正**（写进脚本，供复跑）：控制组 TSV 为**竖线**分隔 ⇒ 首轮 `awk -F'\t'` 使 `ctrl=` 两列恒空，故首轮汇总 `gen_same_as_rf=0/19` **整体作废，禁止解读为「19 枚生成码全部漂移」**；`gen=` 列改落本臂 `lines/md5` 并拆出 `TIMEOUT_10S`。旗标生效性改由 `f016` **三臂 md5 独立实证**（本臂 46,558 行／`bbbd47aa04c7439efc122c1ad823ffc6` ≠ A 臂 45,941 行／`5fdea94d…` ≠ 默认基线 46,782 行／`c8dc9660…`）。
- 新增第 3 枚永久资产 `fuzzy_scripts_720/tmp/opt001_cfgclean_discriminant_tmp.sh`（+ `.tsv` + `_hdr.txt` 代次戳）。**零源码改动**（`optimizer.zig`/`compiler.zig`/`main.zig` 均未动；`git status --short src/` 仅 ` M native_linker.zig` = #74 纯注释批；冻结二进制未重建）；收尾实测 `/tmp/opt001_*`、`aot_compile_*`、`.zigphp_aot_build_*` 均为 **0**，`.php` 计数不变（375／68）。**§7 三项裁决与 OPT-001 §6 P0 主修仍全部待老铁点头**；下一轮非门控候选 = 对 5 枚仍错值形（`f117`/`f161`/`f051`/`f061`/`f135`）用 OPT-001 §5.3 的秒级通道逐枚定机制。

---

**更新日志（残红定机制，2026-10-06，任务 #99）**：

> 视角限定：本轮**不改抬档定价结论**（`release-fast` 67/67 漂移 + 19 枚红、内联单变量只点亮 1 枚 ⇒ 本工单 §4/§7 口径不变），只把 OPT-001 链的**解释力上界**与**再归因的通道成本**钉死。

- **五枚仍错值形逐枚定机制（OPT-001 §5.6）**：四臂（`base`/`licm`/`li5`/`li5nc`）IR-only 签名面扫 + 四臂完整链接因果判别 ⇒ `licm: PASS=0 DIFF=2`／`licmnc: PASS=0 DIFF=2`／`li5: PASS=0 DIFF=5`／`li5nc: PASS=0 DIFF=5`（`opt001_resid_causal_tmp.tsv`）。读数结论：`f117`/`f161`/`f051`/`f135` 四枚与 `f016` **同一条链**（结局 A「merge 寄存器停 `initNull()`」），`f061` 为**新结局 B/R3′**（phi 入边被改写为**异名**前驱块 ⇒ R4 的 `then==else` 折叠从不触发 ⇒ IR 侧签名全盲，只有生成码侧「空臂 PHI」签名 C9 可见）。⇒ §5.4/§5.5 里「**余下必另有机制**」这句对**这 5 枚作废**，改为「**同链不同发射结局**」；本工单**不得**再引用「另有机制」作为「抬档需多条根因」的证据。
- **口径第 2 代（金丝雀实现缺陷更正）**：`reg_N` 编号在**每个 PHP 功能内独立复用** ⇒ 旧「全文有无 `reg_N = `」判定会洗白本站点的零写入。分析器改为**按顶层 `fn` 切区间**后被两支面扫共用 ⇒ 19 形重跑：C1 面**不变**（`chain_hit=9`／`no_hit=10`），新增发射侧签名面 **`emit_hit=6`**，故 OPT-001 §5.4 原「**8 枚＝取错入边**」实为 **3 枚**（`f044`/`f104`/`f134`）。第 1 代落盘已归档（`opt001_canary_sweep_tmp.tsv.r1-global-c2`）⇒ **禁止**再用其 C2 数值做任何比较。
- **40/40 旗标二分 = 负结果（对「抬档前置」的直接含义）**：5 形 ×（引爆臂 + 逐枚关掉 7 枚 CLI 可达 pass）⇒ **全 `DIFF`、`PASS=0`** ⇒ 在 CLI 可达面内**除 LICM 自身外无一枚 pass 关掉能救这五形**，承重点唯一（cfg_cleanup）。剩余候选 `sccp`/`copy-propagation`/`gvn`/`advanced_sccp`/`scalar-replacement`/`rc-elision` **无 CLI 旗标**（`applyPassToggle` `src/main.zig:124-169` 只接受 11 枚名）⇒ **再归因必须插桩**，已越出「零插桩」边界，须老铁点头才可开轮。附带登记：`.tsv` 的 `BISECT_SUMMARY` 七枚 pass 行是 `grep` 模式漏 `no_` 前缀造成的**缺陷产物**（除 `trig` 外恒为全 0），已按原始 40 行 awk 重算并回填脚本 ⇒ 负结果由原始行独立复证。
- **迭代口径更正（影响 §7 裁决项 1 的表述）**：`max_iterations` 默认 **3**（`optimizer.zig:103`；`:191` release-fast=5、`:219` release-small=1、`:142`=1），OPT-001 原隐含「默认 1 轮」为**错** ⇒ 五形实测「3 轮只红 `f117`/`f161`、5 轮五形全红、`base` 全绿」方向成立，但**逐轮（3→4→5）插桩未做**，故 §7 裁决项 1「抬档收益/代价」的定价**不变**，只是「迭代放大」的机制描述从「1→5 轮」更正为「3→5 轮」。
  ⚠ **#101 再更正（本条作废，见 OPT-001 §5.8）**：默认档 = `release_small`（`compiler.zig:140` → `optimizer.zig:65` `.size` → `releaseSmall()`）⇒ **`max_iterations` 实为 1**（`:219`）；`:103` 的 `= 3` 只是结构体字段默认、被四份具名预设全覆盖，**从不生效** ⇒ OPT-001 原文「默认 1 轮」**是对的**，本条 #99 更正属于把字段默认误读成生效值。实证：#101 的 `r1` 臂（显式 `--aot-max-iterations=1`）与 #97 的 `licm` 臂 **19/19 逐枚四签名 Δ 全等**。
  ⇒ **裁决项 1 的「迭代维」定价随之改写（口径见 OPT-001 §5.8.1/§5.8.4）**：逐轮曲线（19 形 × `base/r1..r4` + #100 的 `li5`=r5）实测为**台阶不是斜坡**，且**两把尺封顶轮不同** ⇒
  - **判定面（有无命中）轮 2 封顶**：签名面 `r1=9 → r2=17`（此后 `r3`/`r4`/`r5` 同为 17）、输出面 `r1=7 → r2=18`（`r2`..`r5` 同为 18 红）⇒ **`max_iterations ≥ 2` 即已拿到全部红面**，`release-fast` 的 5 轮相对 2 轮**零额外红面收益**；单调性自证 `CURVE_SIG_NONMONOTONIC NONE`。
  - **幅值面（命中条数）轮 3 封顶**：`r2`/`r3`/`r4`/`r5` **并非逐枚等值**（⚠ 本行原写「逐枚等值」，已被 #101 重算否证并在此更正）——四臂仅在 **15 枚**上等值，`f117`/`f124`/`f171`/`f176` 四枚的 ΔC1/ΔC6/ΔC9 幅值仍在动；从轮 3 起 `r3 ≡ r4 ≡ r5` 逐字节等值。
  - 与 #100 通道的等价性：`r4 ≡ li5`（判定面 + `main.zig` 行数/md5 **19/19 全等**）⇒ 本条与 #100「17/19 签名面」不是两个观测，是同一观测的两个封顶点。
  - 仍未收敛的副作用：`f113`/`f171` 到轮 4 生成码行数仍在变 ⇒ **迭代定点未证**，轮 ≥3 只买漂移与编译时间。
- **三条否证（对本工单的价值）**：陈旧提升（C4/C4h 五形全 0）、`hasStoreInLoop` 盲区（C4bh 全 0）、控制流不敏感提升（C7 **非区分量**，绿臂读数更大）⇒ 五形均无「LICM 提升本身有害」的证据 ⇒ **不得**把「收紧 LICM 提升判据（OPT-001 §6 P1）」当作抬档主修，主修仍是 §6 P0 的删臂准入。
- **收尾实测**：**零源码改动**（`optimizer.zig` `252234ef…`/6877 无 diff、`native_linker.zig` `fbe6382a…`/32797 仍 numstat `5 4`、`ir_generator.zig` `cb53c2da…`、冻结二进制 `1f15e4ce…` **未重建**、`git status --short src/` 仅 ` M native_linker.zig`）；`.php` 计数 375／573／68 **不变、零删除**；`aot_compile_*` = **0**、`.zigphp_aot_build_*` = **0**、`/tmp/opt001_*` 全部删除；OPT-001 侧新增永久资产 5 枚（分析器 `.py` + 面扫/判别/二分 `.sh` ×3 + 归档 `.tsv`），登记于 OPT-001 §7。**门控项不变** = 本工单 §7 三项裁决 + OPT-001 §6 P0/P1（P0 判据另需按 OPT-001 §5.6.7 两条实测收窄改写：准入取数须在 `expandPhiIncomingForRemovedBlock` **之前**；发射侧诊断需扩到「异名前驱块」这一 R3′ 结构，否则漏 `f061` 类）。

---

**更新日志（逐轮定价，2026-10-06，任务 #101）**：

> 视角限定：本轮**只交付 §7 裁决项 1 缺的「迭代维」定价输入**，不改本工单任何档位路线结论（抬默认档 = 不推荐、阈值路线语料收益 0，均维持）；全部读数来自 OPT-001 §5.8 的两层只读实测（19 枚红形 × `base/r1/r2/r3/r4`，`li5` 复用 #100 落盘），**零插桩、零源码改动**。

- **迭代轴是「开关」不是「刻度」**：判定面在**轮 2** 一次性到顶（签名面 9→17、输出面 7→18），轮 3/4/5 相对轮 2 **零额外红面**⇒ 抬 `max_iterations` 的风险只由「是否 ≥2」这一个布尔决定，「抬到 3」与「抬到 5」的红面代价**相同**（`r4` 与 #100 `li5` 的判定 + `main.zig` 行数/md5 19/19 全等）。⇒ 裁决项 1 里任何「保守一点、只抬到 3」的设想**不成立**。
- **默认档真相 = 1 轮，且当前零红面基线靠它维持**：默认 `optimize_level` = `.release_small`（`compiler.zig:140`）→ `.size`（`optimizer.zig:65`）→ `releaseSmall()` 的 `max_iterations = 1`（`:219`）；`optimizer.zig:103` 的 `= 3` 是结构体字段默认，被四份具名预设（`:142`=1／`:163`=3／`:191`=5／`:219`=1）全覆盖，**从不生效** ⇒ 本工单此前「1→5」「3→5」两种措辞统一按 **1 轮基线**重读，#99 那条「默认 3」的"更正"已作废。
- **一条新的连带风险**：饱和点 = 2 而 **`release_safe` = `licm=true`（`optimizer.zig:157`）+ `max_iterations=3`（`:163`）** ⇒ 中间档整体落在引爆区内（**实测推论**：两枚条件都在预设里，逐形红面未扫）⇒ 「只测 `release-fast`」不再是对中间档的免检依据，`release_safe` 面扫登记为遗留（非门控，成本已定价：单形判定面秒级／输出面分钟级，见下）。
- **给 P0 验收省下的成本（可直接用）**：最廉价饱和复现通道 = **默认档 + `--aot-enable-pass=licm --aot-max-iterations=2`**（无需 `--optimize=release-fast`）⇒ 判定面与 `li5` 相同；仅幅值敏感子项需轮 3。实测耗时：层 A 全量 19 形 **14 秒**、层 B 全量（含链接+跑+比对）**1011 秒**（≈52.5 秒／形、13.1 秒／臂，与 #100 的 13.7 秒／臂同量级）。
- **对本工单的否证登记**：轮 ≥3 的生成码仍在漂移且**未收敛**（`f113`/`f171` 到轮 4 行数仍变）⇒ **迭代定点未证**，任何「多迭代 = 更优化」的收益主张在本语料上给不出证据，只给得出编译时间与漂移。
- 收尾：`/tmp/opt001_roundcurve_*` 工作区与日志删除、`aot_compile_*` = 0、`.zigphp_aot_build_*` = 0、`.php` 计数 375／573／68 不变；OPT-001 侧新增永久资产 4 枚（`.sh`／`.py`／`.tsv`／层 A 快照 `.r1-layerA`）。**§7 三项裁决与 OPT-001 §6 P0/P1 仍全部待老铁点头。**
- **#103 追加（逐轮 × `cfg_cleanup` 两维交互·签名侧，读数见 OPT-001 §5.10）**：轮 2／轮 3 与轮 5（#100）三面同为「关 `cfg_cleanup` ⇒ 当期签名命中**全部**熄灭」（17/17，非部分）⇒ 对本工单两点影响：①上条「迭代维定价」与 `cfg_cleanup` 轴**正交** —— 饱和轮（2／3）不改变承重结构，故 OPT-001 §6 P0 的「删臂准入」判据**不必按轮数分档写**；②「顺手把 `cfg_cleanup` 关掉以绕过 P0」这条旁路在**任何 ≥2 轮档位**同样不成立（#98 已在 `release-fast` 否决一次，本轮扩到轮 2/3），且 `f124`/`f134` 在关档臂**直接编译失败**（轮 2/3/5 同现 ⇒ 轮数无关的发射侧硬依赖）—— 关掉它连产物都拿不到。

**更新日志（中间档实测 + 内联阈值定价，2026-10-06，任务 #102/#104/#105/#108）**：

> 视角限定：本轮把 #101 遗留给 PERF-001 的唯一「未做」实测项（`release_safe` 档面扫）**做完并销账**，同时交付 `f152` 的内联阈值定价；§7 三项裁决的推荐口径**不变**，本工单**未改一行源码**。

- **#102 中间档实测 ⇒ 上条「一条新的连带风险」由实测推论升为实测读数，并销账**：68 语料 × 双臂（A = `--optimize=release-safe`；B = 默认档 + `inline --aot-inline-threshold=15` + `licm --aot-max-iterations=3`）⇒ **非绿 18/67**（`diff=17 runtime_fail=1`），红形名单与饱和档 `li5` 的 18 枚**逐枚全等**；两臂 `main.zig` **67/67 逐字节相同**（`ab_same=67 ab_diff=0`）⇒ `release-safe` 的红面**完全**由「轮 3 + `licm`」解释（B 臂已用 4 枚旗标显式复现 `function_inlining`/`inline_threshold=15`/`licm`/`max_iterations=3` ⇒ 等值**不**证明这 4 枚惰性，只证明「预设 ⇔ 旗标」等价）；真正在**联合面**上惰性的，是其余 3 枚不可 CLI 观测的差字段（`copy_propagation`/`gvn`/`max_instructions_per_function`，逐枚面仍待 #104）。⇒ 上条写的「中间档整体落在引爆区（实测推论，逐形红面未扫）」现按实测改记为**已扫且定量**；「只测 `release-fast` 不构成中间档免检依据」这一担忧成立但**不再需要担心** —— 中间档没有独立机制，只有同一个机制。
- **#102 对裁决项 1 的直接影响：「换一档」分支正式关闭**（已在 §7 裁决项 1 正文落地）：三档非绿面实测 = 默认档 **0** ／ `release-safe` **18** ／ `release-fast` **19** ⇒ 默认档与 `release-fast` 之间**没有安全落点**，抬档议题只剩「先修 OPT-001 §6 P0 再抬」一条序。**验收通道结论**：`release-safe` 整档相对「默认档 + 4 枚旗标」零 IR 面差异却多付一枚 `-OReleaseSafe` 链接变量 ⇒ 作为 P0 验收通道**严格劣于** `--aot-max-iterations=2` 的最廉价饱和档（上条已给的结论，本轮给出反向证据）。
- **#102 可观测性风险实测为零**：`ReleaseSafe` 保留溢出/越界 panic 的理论风险（把静默错值变崩溃 ⇒ 看起来更红）**未发生** ⇒ 「抬中间档会让问题变可见」不构成抬档理由，也不构成反对理由。
- **#104 差集查表（门控设计，未开轮）**：`PassConfig` 25 枚字段 × 四份具名预设逐枚实读 ⇒ 默认档（`releaseSmall`）↔ 中间档（`releaseSafe`）的**不可 CLI 观测差集只有 3 枚**（`copy_propagation`、`gvn`、`max_instructions_per_function`），另 6 枚为档间零差（五枚显式 `false` == 结构体默认 + `sccp` 两档同 `true`）⇒ #101/#102 关心的「换一档是否还藏着独立机制」在**联合面**上已答（否），在**逐枚面**上仍待一轮实验；该轮**必须改 `optimizer.zig`** ⇒ **门控**，协议与三臂法（含自证臂）已登记于 OPT-001 §5.11。
- **#105/#108 内联阈值定价（非门控，读数在 CODEGEN-007 §3.7）**：`f152` 的**最小引爆 `inline_threshold` = 35**（`T ≤ 34` 的生成码逐字节 == 冻结基线，含 `releaseSmall` 的 5 与 `releaseSafe` 的 15）⇒ ①本工单 §7「只改阈值（不动默认档语义）」这条路线**与内联缺陷无关**（那条路线碰的是 `native_linker.zig:32446` 的 200KB 尺寸门，不是 pass 集）；②两条独立通道**同向自证**：`release-safe` 里 `f152` 两臂均 **PASS**（相对基线为 `GEN_DRIFT` 46372 行，漂移由「轮 3 + `licm`」承担 —— B 臂同 4 枚旗标产出**逐字节相同** ⇒ A/B 等值证的是「预设 ⇔ 旗标等价」，**不是**「内联开与关」），而阈值阶梯（不带 `licm`）的 `T=15` 与冻结基线**逐字节相同** ⇒ 内联专属红形在中间档不可见，是**阈值 15 < 35** 造成的，不是 `function_inlining` 那枚布尔造成的（⚠ 勿把 A/B 等值读成「内联无面」）；③任何今后「顺手抬 `inline_threshold`」的提案必须先过 `T=35` 这道实测崩点。
- **成本（实测，非估算）**：#102 双臂 67 形 = `ELAPSED=1475s` ⇒ **22.0 秒／形、11.0 秒／臂**（本工单此前引用的「输出面约 17 分钟」低估 45%，真值 24.6 分钟，已按实测更正）；#105 阶梯 14 臂 = 114s + 63s = **177s ⇒ 12.6 秒／臂**；#108 身份轮 = 双臂 `KEEP_TEMP` diff ≈ 26 秒（零插桩 ⇒ 取证不必再走整档抬升）。
- 收尾：`/tmp/c007_f152_thresh_work`／`/tmp/c007_probe_work`／`/tmp/opt001_rs_*`／`/tmp/opt001_roundcfg_run.log` 与本轮 `aot_compile_*`／`.zigphp_aot_build_*` 全部删除；`.php` 计数 **375／573／68 不变、零删除**；`optimizer.zig` `252234ef…`/6877 未改、冻结二进制 `1f15e4ce…` 未重建。**§7 三项裁决与 OPT-001 §6 P0/P1、#104 开轮仍全部待老铁点头。**

---

**更新日志（`cfg_cleanup` 轴三面收口，2026-10-06，任务 #106/#107/#109）**：

> 视角限定：本批**不改**本工单的档位路线结论（抬默认档 = 不推荐、阈值路线语料收益 0、「换一档」分支已闭），只把 OPT-001 §6 P0 与「先修后抬」这条序的**代价面**按实测钉死 ⇒ 读数全部来自 OPT-001 §5.10.1／§5.12／§5.13（只读、零插桩、**零源码改动**）。

- **#106 ⇒ 上界彻底定档**：「关掉整条 `cfg_cleanup` 的新转绿 = **10/19**」现在在**四处同数**（轮 2／轮 3／轮 5／`release-fast`），且 #103 的「命中 100% 熄灭」在**输出侧**同样成立（`r2nc`/`r3nc`/`li5nc` 逐形判定 **19/19 逐名等值**）⇒ 该 10 枚是本工单任何「绕开 cfg_cleanup 换取绿面」提案的**固定天花板**，与轮数、档位、取值通道（签名侧／输出侧）三者皆无关。
- **#107 + #109 ⇒ 一条对裁决项 1 的直接后果：OPT-001 §6 P0 不是「只影响抬档」的修复**（此前 §7 的「先修 P0 再抬」隐含假定 P0 对基线档中性）。实测三面：**IR 侧**真默认档（1 轮、无任何旗标）**25/68** 形命中该判据（Σ71 枚 `phi`）；**发射侧**上界 **23/68** 形改生成码（反向 **43 形可证逐字节保持基线** ⇒ 局部重冻结，不是全语料重冻结）；**语义侧**风险上界 **12/68**（已排除 1 枚 ⇒ ≤11 待逐枚归因 ⇒ **#110 已结案：`NOT_P0_ATTRIBUTABLE = 0` ⇒ 面值 = 11，见下方 #110 块**）。⇒ 「先修 P0 再抬档」这条序的**代价已在基线档上预付**，裁决项 1 的推荐口径不必改写，但**验收面按 OPT-001 §6 的三条改写门走**（默认档 68 输出回归绿为硬门；`diff=0` 只对 `rt=0` 的 43 形；≤23 形定向重冻结）。
- **#109 ⇒ 「顺手关 `cfg_cleanup`」这条旁路在基线档同样否决，且这次是**符号翻转****：同一枚 `--aot-disable-pass=cfg-cleanup`，在「≥2 轮 × 19 红形」面上**新转绿 10、`NEWLY_RED = 0`**（#98/#100/#103/#106），在「真默认档 × 68 语料」面上**新红 17**（`pass=50 diff=10 runtime_fail=3 compile_fail=3 timeout=1`）⇒ **名单外新红 9 枚**（`f007 f027 f033 f067_json f067_min f085 f095 f110 f178`，含 `f178` **SIGSEGV `exit=139`**）。⇒ 该旗标的符号**由档位决定**，任何「拿它当临时逃生口」的提案在**两个方向上都不成立**：抬档时它救不全红面（上界 10），基线档时它直接**制造**红。
- **#109 ⇒ 「发射侧对 `cfg_cleanup` 有硬依赖」正式定为档位无关常量，并新增第三枚形**：#98 在 `release-fast` 首见（`f124`/`f134`）、#103 证轮数无关、#106 复现于轮 2/3、本轮在**真默认档 1 轮**上同样砸编译，并新增 `f085`；报错形态统一为 `[AST-DIRECT-FAIL] function=X unprocessed blocks: N:if_merge_*` ⇒ 某些汇合块必须先被 cfg_cleanup 折叠，AST-direct 生成器才认。⇒ 本工单 §4/§7 任何涉及「关某个整理型 pass」的路线，前置闸门 = 这枚硬依赖，**不是**可协商的性能取舍。
- **对「先修后抬」的可执行拆分（OPT-001 新增 §6.1）**：P0 的两行风险不对称已量出 ⇒ **P0-a（发射侧「静默改可见」诊断）零 CFG 改动、结构性零新红风险、可独立先落地**；**P0-b（R2 删块判据收紧）碰 CFG**，才是消红面的那一条 ⇒ **抬档解锁仍依赖 P0-b**，只落 P0-a 不减红面，但会让 P0-b 的风险以编译期报错而非静默错值显形。⇒ 给老铁的序：**P0-a → P0-b → 再谈抬档**（三者的门控状态都不变，仍等点头）。
- **成本（实测，非估算）**：#106 38 臂 `ELAPSED=452s` ⇒ **11.9 秒／臂**；#107 125 条双臂计数 `ELAPSED=4s` ⇒ **0.03 秒／臂**；#109 68 形两层（层 1 双臂 + 层 2 全编译链接运行 + PHP 真值）`ELAPSED=724s` ⇒ **10.7 秒／形** ⇒ 与 #102 的 22.0 秒／形、#105 的 12.6 秒／臂同量级；本批三轮**均未重建二进制**。
- 收尾：**零源码改动**（`optimizer.zig` `252234ef…`/6877 无 diff、`native_linker.zig` `fbe6382a…`/32797 仍 numstat `5 4` = #74 纯注释批、`ir_generator.zig` `cb53c2da…`、冻结二进制 `1f15e4ce…` 未重建、`git status --short src/` 仅 ` M src/aot/native_linker.zig`）；OPT-001 侧本批新增永久资产 **10 枚**（#106 3 枚 + #107 5 枚 + #109 2 枚），登记于 OPT-001 §7；`.php` 计数 **375／573／68 不变、零删除**；`/tmp/opt001_*` 工作区按显式路径删除。**§7 三项裁决、OPT-001 §6.1 的 P0-a/P0-b、P1、#104 开轮、REF-003 #40、CODEGEN-006 #81/#84 —— 全部仍等老铁点头。**

**更新日志（`cfg_cleanup` 轴第四面 = 逐枚归因面收口，2026-10-06，任务 #110）**：

> 视角限定：本批同样**不改**本工单的档位路线结论，只把上块遗留的「≤11 待逐枚归因」这个**待定数**换成实测面值，并修正上一条「P0-a 结构性零新红风险」的字面强度 ⇒ 读数来自 OPT-001 §5.14（只读、零插桩、**零源码改动**）。

- **#110 ⇒ P0-b 的语义风险面值定为 11，不是「大概几枚」**：对 `rt>0 ∧ 层 2 非绿` 的 11 枚做「NC ⇄ ON `main.zig` 按顶层 `fn` 区间取 md5 ⇒ 漂移函数集合 ∩ P0 拒删站点函数集合」⇒ `NOT_P0_ATTRIBUTABLE = 0`、`UNDETERMINED = 10`、`NC_NO_EMISSION = 1`（`f124`，NC 臂无生成码）⇒ 上块「已排除 1 枚 ⇒ ≤11」的**待定性质未消除**，P0-b 落地即把 **11 枚风险压进基线档**。且 `P0SITE_FULLY_DRIFTING = 10/10`（`inter == p0_funcs` 恒成立）⇒ **「只放行不相交函数」的逐函数白名单这条退路实测关闭**，本工单不能指望 P0-b 的风险被白名单摊平。⚠ `Σdrift_only_functions=30` 是 NC（关整条 pass）独改的函数数 ⇒ 只作上界幅值，**禁止**反向当作「P0 一定改这 30 枚」。
- **#110 ⇒ 上块「P0-a 结构性零新红风险」按字面否证（次序不变，多一步前置）**：真默认档上 C6／C9 的**绝对在场**非 0 的两枚 = `f135`（`c6=3`／`c9=1`）与 `f161`（`c9=1`），而这两枚**当前是绿形**（该语料默认档 `Total=68 Pass=67 Skip=1`，非绿清单为空）⇒ 若 P0-a 的守卫写成「PHI 标记在、本功能区间内无正常流赋值即报错」，会**当场砸编译两枚绿形**。⇒ P0-a 的「零 CFG 改动」仍成立，但**判据形式必须收窄**，且发射器单次编译看不到对照臂 ⇒ Δ 口径要转写为 IR 侧可判条件。**给老铁的序不变：P0-a（先收窄判据）→ P0-b → 再谈抬档。**
- **#110 ⇒ 非门控通道已穷尽**：OPT-001 的四面（IR 命中面 #107／发射面 + 语义面上界 #109／逐枚归因面 #110）全部走零插桩 CLI 拿到手，后续任何进一步定面（把「NC 关整条 pass」换成「只拒这一枚删块」的真 P0 臂）都**必须改 `optimizer.zig`／`native_linker.zig`** ⇒ 即门控。⇒ 本工单 §7 裁决项 1 的「先修 P0 再抬」这条序，其**代价定价工作已结束**，剩下的只是裁决。
- **成本（实测，非估算）**：#110 全轮 11 形 × 双臂 `--no-link` + `--emit-ir` + 逐形清理 ⇒ **`ELAPSED=3s`** ⇒ 逐枚归因协议比 OPT-001 原登记的「2 × 12 秒／形」（那是 KEEP_TEMP 全编译通道）**便宜两个数量级**；后续同类对账不必再用 KEEP_TEMP。
- 收尾：**零源码改动**（四枚戳同上块逐枚等值、二进制未重建、`git status --short src/` 仍仅 ` M src/aot/native_linker.zig`）；OPT-001 侧新增永久资产 **3 枚**（`opt001_p0site_face_tmp.sh`／`opt001_p0site_intersect_tmp.py`／主表 `.tsv`），登记于 OPT-001 §7；`.php` 计数 **375／573／68 不变、零删除**；`/tmp/opt001_p110` 工作区按显式路径删除。**§7 三项裁决、OPT-001 §6.1 的 P0-a/P0-b、P1、#104 开轮、REF-003 #40、CODEGEN-006 #81/#84、CODEGEN-007 §5 A/B/C/D —— 全部仍等老铁点头。**
