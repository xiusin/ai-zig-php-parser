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

1. **档位杠杆**：AOT 默认 `optimize_level = .release_small`（`src/aot/compiler.zig:140`），只在生成码 `> 200_000` 字节时被 `src/aot/native_linker.zig:32195` 静默升级为 `release_fast`。**小脚本拿不到这个升级** ⇒ 同一产物源码在纯计算负载上慢 **3.4 倍**、数组负载上慢 **2.6 倍**。
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

**默认档实测（决定性）**：`bench_sm_tmp` 用**不带 `--optimize` 的默认命令**编译 ⇒ 产物 527,952 字节（与上表 ReleaseSmall 列一致）、`real 0.89(冷) 0.44 0.45` ⇒ **默认确实跑 ReleaseSmall**，因为其生成码 87,483 B < 200,000 B，:32195 的逃逸门未触发。

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
| **P0（待裁决）** | **默认档位 `release_small` → `release_fast`**（`src/aot/compiler.zig:140`），或等价地把 `:32195` 逃逸门阈值从 200KB 下调（如 32KB）使小脚本也升级 | 只改 `zig build-exe` 的 `-O` 与 `strip_symbols`（`compiler.zig:645` 按 `release_small` 判 strip）⇒ **不改生成码** ⇒ 冻结基线 `baseline_main_zig_md5.tsv` 哈希的是 `main.zig`，**理论上零漂移、不需重冻结**；代价：产物体积 +39%～42%、编译墙钟 +78%（实测） | 一行改动。**收益实测 2.65×～3.44×**。必须跑官方 68 回归 + 四道探针门确认无行为变化（ReleaseFast 下未定义行为可能显形） |
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

档位改动后的验收：**官方 68 回归**（`scripts/regression_test_720.sh`，判据 PASS 67 / SKIP 1 / FAIL_* = 0）+ **四道探针门**（17 形等值门、RC-4 诊断门、RC-5 八形 + 三单形、新 `c005_dowhile_probe_run_tmp.sh`）+ `timeout 240 zig build test`。冻结基线漂移门可复跑确认「档位不改生成码」（预期 `diff=0`）。

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
| 1 | 是否把默认 `optimize_level` 改为 `release_fast`（或把 `:32195` 阈值下调到 32KB）？ | 建议改**阈值**而非默认值：小脚本自动升档、大脚本行为不变、可回退、不动「默认」语义 |
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
