# native_linker.zig 自递归入口审计报告（任务 #23，Plan B 前置）

- 日期：2026-09-27
- 对象：`src/aot/native_linker.zig`（发射器全量函数扫描）
- 背景：#22（AOT-CODEGEN-004）以 Plan A（512MB 大栈线程）止血后，为 Plan B（迭代化根治）立项做全量递归面盘点
- 帧大小基准：`generateLabelDrivenBlockRange` 实测 ~3.8KB/帧（#22 崩溃栈反推）；Plan A 栈预算 512MB ⇒ 同尾链上限 ≈ **13.4 万组**

## 1. 真自递归函数清单（自调用在本函数体内，脚本扫描定义区间判定）

| 函数 | 自调用点 | 深度增长驱动 | 风险类别 |
|---|---|---|---|
| `generateLabelDrivenBlockRange`(L7152) | **21 处**：7921/8075/8322/8513/8851/8883/9015/9201/9265/9291/9492/9581/9690/9737/9745/9791/9839/9968/10154/10216/10221 | 混合，见 §2 | **A 类 11 处 = 无界线性** |
| `generateCondBrBlock` | 24538/24762（子 cond_br，child_indent）、24880（merge 后继同 indent 尾随） | 24880 沿 elseif 链线性 | A 类（源法链长） |
| `generateBrChain` | 25185（`!return_generated` 时沿 br→br 链） | br 链长线性 | A 类 |
| `generateForFromLabels` | 13536（for 体内 sibling else `[blk_i..end_idx)`） | 链长线性 | A 类 |
| `writeConstantValueInlineDepth` | 31629/31631/31635（数组常量元素/键） | **数据嵌套**深度 | B 类（有界） |
| `resolveTraitExports` | 2579（trait 继承链） | trait 层级 | B 类 |
| `irTypeToZigTypeString` | 3512（类型嵌套） | 类型结构 | B 类 |

互递归说明：`generateLabelDrivenBlockRange ↔ generate{While,For,Foreach,DoWhile}FromLabels / generateIfFromLabels` 互为调用（blockrange 分派循环/条件生成器，生成器再回入 blockrange），深度受**语法嵌套层数**约束（源码嵌套，实践 <100），不构成线性风险；循环生成器内部对 blockrange 的 `[x..loop_end)` 调用在循环体 sibling 链上同样呈 A 类形态（如 12516/12679/12769/13023），但均计入同一 512MB 预算。

## 2. blockrange 21 处自调用分类

**A 类（SAME-TAIL：`[next..end_idx)` 同尾推进，栈深随 sibling if/else 组数线性增长）— 11 处：**
8075（else==merge 短路链，#22 实测崩溃点）、9015、9201、9265、9291、9492、9581、9968、10154、10216、10221
其中 9015/9968 为 `_ = try` 形（调用后主循环靠 processed 跳过），8075/9201/9291/10154/10221 调用后存在**逐站点定制的 `then_returned/else_returned/break` AND/OR 状态合并**——迭代化必须复现「嵌套合并 folds」语义，非简单续循环。

**B 类（narrow range：`[x..then_end]`、`[x..nmi+1]`、`[x..cs18_end]` 等子区间）— 10 处：**
7921、8322、8513、8851、8883、9690、9737、9745、9791、9839 —— 深度 = 语法嵌套层数，有界，安全。

## 3. 规模实证（#21/#22 探针数据）

| 探针 | sibling 组数 | 递归深度实测 | 结果 |
|---|---|---|---|
| 28k/every-10（stack_deep） | ≈2800 组 | 崩溃时 4322 帧（≈16MB）；改后完整发射 110.8 万行 | Plan A 下深度 ~11MB 用量 |
| 16k/every-40 | ≈800 组 | 未崩 | 43.4 万行发射 |
| 68 回归语料 | ≤数十组 | 无风险 | — |

线性外推：Plan A 512MB ⇒ ~13.4 万组 sibling 链上限；对应单函数 >270 万条 PHP 语句——该规模下 `zig build-exe` 吞吐（#21 P2，434k 行已 >40min）早已成为不可达前置瓶颈。**A 类站点在 Plan A 预算内不存在可达的溢出路径。**

## 4. 结论与建议

1. **溢出路径已全部收口**：所有无界线性递归都发生在 blockrange/循环生成器/BrChain 的 SAME-TAIL 形态内，且都运行在 Plan A 的 512MB 线程栈上；真实 PHP 规模离 13.4 万组上限差 2 个数量级，且更远处先撞上 zig build-exe 吞吐墙。
2. **全量迭代化（原义 Plan B）= 11+ 站点 × 各异的状态合并协议重构**，664KB 状态机侵入风险与「零收益的理论加固」不成比例；不建议按原范围实施。
3. 建议的**分阶段替代方案**：
   - **P1（低风险，立即）**：blockrange 加确定性深度计数器（入口 ++/defer --），阈值 60000 帧（≈228MB，< 512MB 预算），超限输出 `[AOT-DEEP-CHAIN]` 结构化错误并**干净失败**（把理论尾段从 segfault 变成可诊断错误；零性能成本，同尾链上每帧一次整数比较）。
   - **P2（按需，暂缓）**：仅当真实语料触到 P1 金丝雀时，再对**实际触发的那一类 SAME-TAIL 站点**做逐点迭代化（每次改造以 68 语料 + 三档预算门探针 + stack_deep 的 main.zig **逐字节等值**为准入门槛）。
4. B 类/互递归站点无需处理；`writeConstantValueInlineDepth` 若未来支持超深嵌套常量数组（>10 万层）再加同款守卫。
