# AOT-CODEGEN-012 R-248：抽象方法直接调用的可捕获性（F-156-b/F-156-c）

- 日期：2026-10-24（R-248；F-156-b、F-156-c 闭环）
- 代次锚：`nlk 15514e9f7e90fcca640c1274c3ddc6c4`／`irg f4f2ae15b02f61615115ed5d1732479c`／`tpl 9fee311c…`／`ir bcf6823a…`／`parser 70e80f18…`／`opt 745e4bd4…`（未提交）
- 状态：全部**未提交**

## 1. 高层摘要（TL;DR）

R-247 让接口方法有了“调用即抛”的函数体，但两条路径仍不符 PHP：①`try { I::m(); }` 中抽象方法抛出的 Zig error 穿过 PHP catch（跨帧不可捕获，rc=255）；②抽象类抽象方法没有 body，生成的是**静默返回 null** 的空体，`A::sm()` 悄无声息。本批修正静态直调在 try 语境的发射形态，并让抽象类方法复用“抛 Error”的合成体；同时把 abstract 措辞的优先级放在“非静态方法静态调用”之前。

- C294（7 臂）**7/7**；回归 **68/68**；C293/C276 守卫不变。

## 2. 影响范围

| 维度 | 影响 |
|---|---|
| 语义面 | 抽象/接口方法直接调用返回可捕获 `Error`；finally/跨函数传播与 PHP 一致 |
| 发射面 | **所有** try 内静态直调改为 `catch` 形态（置 null + hasException 路由） |
| 抽象方法体 | 抽象类无 body 方法不再静默返回 null，改为抛 Error |
| 措辞 | 抽象优先于“Non-static method”判定 |
| 未覆盖 | 动态类名静态调用（`$c::m()`）维持既有形态（F-18） |

## 3. 核心变更

| # | 位置 | 变更 |
|---|---|---|
| 1 | [native_linker.zig:25074](file:///Users/wangjianjun/products/parser/src/aot/native_linker.zig#L25074) | try 内静态直调：`@"C::m"(…) catch Value.initNull()` / `catch {}`，随后 hasException 路由；try 外保持 `try` |
| 2 | [native_linker.zig:4123](file:///Users/wangjianjun/products/parser/src/aot/native_linker.zig#L4123) | 新 `isAbstractMethod`：扫描 IR 类型表判抽象方法 |
| 3 | [native_linker.zig:24992](file:///Users/wangjianjun/products/parser/src/aot/native_linker.zig#L24992) | 静态直调分支在非静态判定**之前**处理 abstract 措辞（可捕获 Error） |
| 4 | [ir_generator.zig:2753](file:///Users/wangjianjun/products/parser/src/aot/ir_generator.zig#L2753) | `generateMethodDecl`：`is_abstract && body==null` ⇒ `generateAbstractMethodFunction` |
| 5 | `fuzzy_scripts_720/tmp/c294_abstract_call_gate_tmp.sh` | 新永久侧门 7 臂 |

## 4. 可视化概览（Code & Logic Map）

```mermaid
flowchart TD
  A["静态直调 C::m()"] --> B{"isAbstractMethod(C,m)?"}
  B -->|是| C["throwThrowable(Error, Cannot call abstract method C::m())"]
  B -->|否| D{"staticEmitCallIsIllegal?"}
  D -->|是| E["throwThrowable(Error, Non-static method …)"]
  D -->|否| F{"在 try 语境?"}
  C --> G{"在 try 语境?"}
  E --> G
  F -->|是| H["@\"C::m\"(…) catch initNull → hasException 路由到 catch"]
  F -->|否| I["try @\"C::m\"(…)（未捕获 → fatal）"]
  G -->|是| H
  G -->|否| I
```

```mermaid
sequenceDiagram
  participant S as 脚本(try)
  participant G as 生成码 main
  participant F as @"I::m"
  S->>G: try { I::m(); }
  G->>F: 调用（catch null）
  F-->>G: 置 Error 后返回 error.RuntimeError
  G->>G: catch → hasException()
  G->>G: current_block = catch 块
  G-->>S: 捕获到 Error（后续代码继续）
```

## 5. 详细变更分析

| 层 | 文件/位置 | 说明 |
|---|---|---|
| 发射器 | `native_linker.zig` | 静态直调三处（有返回/无返回/无结果）全部按 try 语境分叉 |
| IR 生成 | `ir_generator.zig` | 抽象方法统一走抛错合成体 |
| 门 | C294 | 接口/抽象静态/抽象实例静态调用/finally/跨函数/invoke 守卫 |

**关键约束**
- try 内**不能**裸 `try @"..."`：Zig error 穿过 PHP catch 会成未捕获 fatal（与 `:19492` 的既有注释同因）。
- 抽象措辞优先于非静态措辞（PHP 实测 `A::m()` 报 abstract）。
- try 外语境保持 `try`，让未捕获异常冒到 main 成 fatal，与 PHP 一致。
- 抽象类无 body 方法必须复用 R-247 的 `generateAbstractMethodFunction`，不得保留空体（空体是静默错值）。

## 6. 影响与风险评估

| 项 | 结论 |
|---|---|
| 是否破坏式变更 | 修正不可捕获/静默两类错值；普通静态调用行为不变 |
| 门 | C294 **7/7**（自证 7 CF）；C293 7/7、C276 12/12 |
| `zig build test` | 21/21 steps、326/326、rc=0（`/tmp/zigtest_R248.log`） |
| 主回归 | **PASS=68 FAIL=0**、`SELF_CHECK_OK rows=68 uniq=68`（`c299_regression_R248_tmp.log`） |
| 风险 | 中低；改动覆盖所有 try 内静态直调，方向为 PHP 对齐，已全量回归 |
| 性能 | 每个 try 内静态直调多一次 `catch` 分支（零成本栈展开已在 ReleaseFast 关闭）；无额外分配 |

**复测路径**：C294（自证 7 CF → 7/7）→ C293/C276 → 主回归 → `zig build test`。

## 7. 遗留问题 / 潜在问题

1. 动态类名静态调用（`$c::m()`）仍走 `php_call_static` 旧形态（F-18 已登记）。
2. 抽象方法的 attributes/返回类型元数据沿用 `getMethodMeta`，未单列臂。
3. try 内静态直调改为 catch 形态后，若被调函数返回 `error.OutOfMemory` 等非 PHP 异常，也会被置 null 并检查 `hasException`（此时无异常 Value）⇒ 继续执行；属极端 OOM 路径，未单列。

## 8. 后续开发 / 优化建议

| 优先级 | 建议 | 影响面 | 落地成本 |
|---|---|---|---|
| P1 | F-155：函数级/直接构造/trait 方法参数元数据统一 | Reflection 参数族 | 中 |
| P2 | F-18：动态类名静态调用的 ctx/可捕获性 | 静态分发族 | 中 |
| P2 | F-154：转换运算符＋静态属性优先级（待裁跨模式） | 共享 parser | 中 |
| P3 | F-62f-opt 可选参哨兵 | 全可选参族 | 中 |
