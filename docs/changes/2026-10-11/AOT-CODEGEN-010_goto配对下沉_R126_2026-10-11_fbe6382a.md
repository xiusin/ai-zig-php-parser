# AOT-CODEGEN-010 goto 配对下沉（函数体/块内循环解除登记）_R126_2026-10-11_fbe6382a

## 1. 高层摘要（TL;DR）

1. **R-125 的 label→closer 配对走查从 `generateMainFunction` 下沉为共用助手 `generateStatementListGotoAware`**，`generateBlock` 同步接线 ⇒ **函数体/花括号块内的规范后向 goto 循环同批解除登记**（R-125 的作用域边界收口）。
2. **验收（链 VI，2026-10-11 01:32:11 报表）**：门 D8 `defect_red=0 guard_same=14`；门 H `face=0 noface=79 confounded=0 inverse_face=0`；影子 68 语料 md5 **68/68 一致**；门 I **tree/bc 逐项不变**；主回归 **Pass 67 / Skip 1**。
3. **探针**：函数体 goto 循环 f1→`3`、f2→`zz2`、函数体+顶层混合 f3→`6` 全绿。
4. 本轮源码净变化 = R-125 配对循环重构为助手 + `generateBlock` 接线（ir_generator 单文件，累计未提交 +227/−13 含并行会话 parser 批）；二进制 `85b51931d0f5b79f2d681e1481a1ff3e`。

## 2. 影响范围 / 核心变更

| 项 | 内容 |
|---|---|
| 变更 | ① `generateStatementListGotoAware`（R-125 顶层配对循环原样上提为方法）；② `generateMainFunction` 改调该助手（行为逐字节等价）；③ `generateBlock` 改调该助手（新增能力：块内规范后向 goto 降级为 do-while IR） |
| 作用域 | 全部语句列表（顶层/函数体/花括号块/if-while 体等经 generateBlock 的位置）；配对判据不变（无 else 且 then 仅一条 goto L / 裸 goto L） |
| 零漂移依据 | 语料 goto 0 处 ⇒ 配对逻辑零触发；非规范形态 flush = 原序生成（现状行为） |

## 3. 验收读数（链 VI）

| 门 | 读数 |
|---|---|
| D8 | `defect_red=0 guard_same=14 compile_fail=0 residue=0` |
| H | `face=0 noface=79 confounded=0 inverse_face=0 inverse_noface=21 probe_compile_fail=0 ctrl_compile_fail=0` |
| H2/I/E/F/G | 与 R-5 代注册值一致（tree/bc 逐项不变） |
| 影子 | `total=68 same=68 diff=0` |
| 主回归 | Total 68 / Pass 67 / Skip 1 |

## 4. 遗留与建议

| 优先级 | 事项 |
|---|---|
| **P0** | 「提交」：三批分票点名（并行会话 R-3/R-5 parser 批、R-125+R-126 goto ir 批、工单/门/文档） |
| P2 | 非规范 goto 形态（双 goto/带 else closer/多标签）——需发射器 goto 形状改造（#122d 定论），独立评审 |
| P2 | 命名参数 CI、运行期查名族折形（罕见面，维持登记） |
