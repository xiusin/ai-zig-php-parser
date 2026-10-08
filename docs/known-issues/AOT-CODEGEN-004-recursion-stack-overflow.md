# generateLabelDrivenBlockRange 深递归栈溢出（编译器进程段错误）

**问题 ID**: AOT-CODEGEN-004  
**优先级**: P0（高，编译大函数即崩）  
**状态**: 主路径已根治（Plan B / B-lite，2026-09-28），Plan A 大栈保留纵深防御；臂内 10 站 = P2
**发现日期**: 2026-09-27（mem2reg 预算门压力探针 #21 过程中复现）

---

## 问题描述

`src/aot/native_linker.zig` 的 `generateLabelDrivenBlockRange` 对 **sibling if/else 链**（同一函数内顺序排列的 if_merge 块组）按链长做**深度递归**：

- `native_linker.zig:8075`：`if (!else_has_real_body) if (nested_else_idx) |nei| { ... try self.generateLabelDrivenBlockRange(writer, func, nei, end_idx, ...); }` — else==merge 短路场景把后继 sibling 块整段递归进去；
- `native_linker.zig:7257`：同型递归调用。

> **行号口径（2026-10-03 实测复核）**：上述两行是 **2026-09-28 代次**。当前树（`0ff09cf` + RC-5 工作区改动，`native_linker.zig` 32492 行）中该函数与本次根治代码的实测位置为：
>
> - `generateLabelDrivenBlockRange` 函数体 `:7188`–`:10651`（下一个函数 `materializeEdgePhi` 起于 `:10652`）；
> - B-lite 站点（原 `:8075`）：短路场景守卫 `if (!else_has_real_body) if (nested_else_idx) |nei| {` = `:8153`，`!processed.contains(nei)` = `:8154`，WHY 注释 `:8157`–`:8164`，缺口不变量判定 `:8165`–`:8172`，同帧续走 `range_start = nei; i = nei; continue;` = `:8173`–`:8176`，兜底原递归 = `:8178`；
> - `range_start` 影子副本：声明 `:7201`（口径注释 `:7199`–`:7200`）、defer 回跳判定读 `:7230`、latch 判定读 `:10436`。
>
> **`:7257`「同型递归调用」未能证实**：在 `908a3a0`（2026-09-20，29272 行树）该行为 `try writer.print("{s}}}\n", .{if_indent});`，在 `125aa78`（2026-09-29，32119 行树）该行为 `for (block.instructions.items) |inst| {`，当前树 `:7257` 为 `// 检查是否是 if 语句` 注释 —— **三代次抽样中该行均不是递归调用语句**（崩溃发生于 2026-09-27 的未提交工作态，无对应提交可比）。因此下方「崩溃特征」代码块里的 `native_linker.zig:7257 ...` 引文**按原样保留作历史日志**，但**不得再作为定位依据**；本工单的定位口径以本节实测锚点为准。

每帧约 3.8KB（多 ArrayList/参数上下文），sibling 链每 2 个 if 组约 1 帧。默认主线程栈（macOS 8MB）在链深 ≈1000-2000 组时溢出，**php-interpreter 编译进程自身段错误**（非产物运行期问题）。

## 复现代码

`fuzzy_scripts_720/tmp/stack_deep_probe_tmp.php`（永久探针，勿删）：28000 个加法单元、每 10 单元一组 `if` + `if/else`（≈5600 个顺序 if_merge 块组，big() 约 13 万指令）。

```
cd /Users/wangjianjun/products/parser
timeout 900 zig-out/bin/php-interpreter --compile --no-debug-info fuzzy_scripts_720/tmp/stack_deep_probe_tmp.php
```

## 崩溃特征（改前实测）

```
Segmentation fault at address 0x16e1bb488          ; 栈守卫页附近低地址
... native_linker.zig:8075 in generateLabelDrivenBlockRange__anon_17481 (×4322 帧)
... native_linker.zig:7257 ...
exit=134，崩溃发生于发射阶段中段（wall ≈ 542s）
```

对照：16000u/every-40（≈800 组 sibling）不崩但发射 43.4 万行 main.zig；28000u/every-10 必崩。

## 修复（Plan A，2026-09-27 已落地）

`src/main.zig`：`--compile` 路径的 `runAOTCompilation` 调用包进显式 **512MB 大栈工作线程**（`std.Thread.spawn(.{ .stack_size = 512MB }, ...)` + join + `try ctx.result` 错误传播）。编译管线单线程、无 thread-local 依赖；栈为虚拟内存惰性提交，不增加常驻内存。512MB 支撑链深 ≈13 万组，覆盖现实 PHP 函数。

验证：28000u/every-10 探针改后可完整发射 110.8 万行 main.zig（md5 跨 run 一致）、正常进入 `zig build-exe`，段错误消除；68 脚本正式回归无差异。

## 根治（Plan B / B-lite，2026-09-28 已落地）

#23 逐站精读结论：11 个同 end_idx 尾递归站中**仅原 8075 站（sibling if/elseif 链 else 区间走）为纯尾委托**——子帧与父帧同 indent/end_idx，呼叫后 fold `(t∧e)∨e ≡ e` 布尔恒等、父帧零 emission；其余 10 站（9015/9968 chain_unwind 对、9201/9265/9291/10154/10216/10221 hop 家族、9492、9581）为「臂内交错续延」，迭代化等价于动作栈 VM 级改造（高风险，暂缓）。经用户裁决取 **B-lite** 口径：

- `generateLabelDrivenBlockRange` 入口 `range_start` 影子副本（defer/latch 两处判定改读）；
- 8075 站缺口不变量（`[i+1, nei)` 全 processed）成立时 `range_start=nei; i=nei; continue` 同帧续走，**零新增栈帧**；不成立回退原递归（兜底）。

取证：68 语料 flatten=34/fallback=0；28000u 深链探针 flatten=2799/fallback=0（链深不再进栈）；72 项发射 main.zig 逐字节 md5 与冻结基线全等；正式回归 67+1SKIP+0FAIL；确定性巡检 mismatch=0；副产品深链发射墙钟 25min→14.5min。详见 `docs/changes/2026-09-28/AOT编译稳定性_labelDrivenBlockRange_8075纯尾委托同帧迭代化_B-lite_2026-09-28_908a3a0.md`。

Plan A 大栈线程保留为纵深防御（臂内 10 站仍每顶层结构 1 帧，512MB ≈ 13.4 万帧上限）。

## 遗留（P2）

- 10 个臂内交错续延站的动作栈 VM 根治（把呼叫后交错过 emission 拆解为类型化动作序列），仅当出现 >10 万结构规模的真实输入时立项。

> **遗留站当代锚点（2026-10-03 实测）**：当前树 `generateLabelDrivenBlockRange`（`:7188`–`:10651`）内自递归调用点共 **21** 处，其中**同 `end_idx` 尾递归站实测 11 处** —— 已由 B-lite 迭代化的 `:8178` ＋ 仍待根治的 10 处：**`:9118` / `:9304` / `:9368` / `:9394` / `:9595` / `:9684` / `:10071` / `:10257` / `:10319` / `:10324`**（计数与站点数均与 2026-09-28 登记的「11 个同 end_idx 尾递归站」一致）。映射由逐行比对 `125aa78`（2026-09-29，32119 行树）得到，原登记行号对当前树**统一漂移 +103**：`9015→9118`、`9201→9304`、`9265→9368`、`9291→9394`、`9492→9595`、`9581→9684`、`9968→10071`、`10154→10257`、`10216→10319`、`10221→10324`；`9015/9968` 这对 chain_unwind 站在当前树仍为 `_ = try self.generateLabelDrivenBlockRange(...)` 形态（`:9118`、`:10071`）。

## 锚点代次刷新（2026-10-05，当前工作区代次 `fbe6382a`／32797 行实测；只读巡检，零代码改动）

上段（2026-10-03）登记值属 RC-5 代次，其后 A／D／R9-B 三批（`497edc6`）与 #74 注释批插行 ⇒ 行号已漂移。**本轮按符号与调用形态重新 grep**（非偏移推算），历史值保留不改写，动手时以本表为准。

| 锚点 | 旧登记（2026-10-03） | **当前树实测** | 实测依据（该行内容） |
|---|---|---|---|
| 主崩溃站（B-lite 迭代化头） | `:8075`（`if (!else_has_real_body) if (nested_else_idx) |nei| {`） | **`:8396`** | 该行逐字为同一条件；其内 `gap_open` 声明与缺口扫描在 `:8408–:8415`，同帧续走的 `if (!gap_open)` 块在 `:8416–:8420`（改写三行 `range_start = nei;`／`i = nei;`／`continue;` = `:8417–:8419`） |
| 该站的递归后备调用 | `:8178` | **`:8421`** | `try self.generateLabelDrivenBlockRange(writer, func, nei, end_idx, ...)` |
| `generateLabelDrivenBlockRange` 函数边界 | `:7188`–`:10651` | **`:7431`–`:10936`** | `grep -n "fn generateLabelDrivenBlockRange"` = 唯一命中 `:7431`；下一函数 `materializeEdgePhi` 起于 `:10937` |
| 同 `end_idx` 尾递归站集合（11 处，含已迭代化那处） | `8178` ＋ `9118`/`9304/9368/9394/9595/9684`/`10071` ＋ `10257`/`10319`/`10324` | **`8421`** ＋ **`9374` / `9560` / `9624` / `9650` / `9851` / `9940`** ＋ **`10356` / `10542` / `10604` / `10609`** | 逐行过滤 `awk 'NR>=7431 && NR<=10936 && /self\.generateLabelDrivenBlockRange\(/'` 后取第二实参为 `end_idx` 者，命中数 **11** ⇒ 与旧登记**计数完全一致**，仍为「1 处已 B-lite ＋ 10 处待根治」 |

**状态判定不受行号漂移影响**：主崩溃路径（长 sibling if/elseif 链按链长累加栈帧）的 B-lite 同帧迭代化实测**仍在**（`gap_open` 守卫 + `range_start/i` 改写两件套内容已核对），§复现 的探针门 `c005_probe_run_tmp.sh` 在本轮十二腿实测 `PROBE_DONE total=17 same=17 differs=0` ⇒ 「主路径已根治」维持；P2 遗留仍是 **10 站**（动作栈 VM 根治），未因行号漂移改变范围。`:7257`「同型递归调用」一栏本轮**仍未证实**（该处现为 `std.mem.eql(...)` 片段的续行），维持原「历史读数、禁止再用作定位锚」结论。
