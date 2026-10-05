# 结构化控制流生成器的 continue 插入问题

**问题 ID**: AOT-CODEGEN-002  
**优先级**: P0（高）  
**状态**: **CLOSED（2026-10-01 当前树实测 + 代码取证；2026-10-03 在 RC-5 v2 二进制上复测通过）** —— 原工单复现（循环体内两个顺序兄弟 `if`）即探针 `fuzzy_scripts_720/tmp/c005_k_seq_if_for_tmp.php`，`b21cdfd` 树实测 **`K x=c` 与 `/opt/homebrew/bin/php` 逐字节等值**（`RUN_RC=0`），并属等值探针门的常驻一项（该门现为 **17 形**：10 个 `c005_*` + 7 个 `ref002_iso_*`）。**2026-10-03 复测**：RC-5 方案 B 落地后 17 形门 `PROBE_DONE total=17 same=17 differs=0` ⇒ 本工单 CLOSED 在新树仍成立。**重要更正**：本文 §临时解决方案 的 `if (false)` 禁用结构化控制流**已不是现状** —— 该门控现为 `if (true)`（`native_linker.zig:17507`，2026-10-03 实测；附失败回滚 :17524–17528），结构化生成器**已重新启用**，缺陷由 merge 块判定真修（见 §修复落地）。
>
> **代次刷新（2026-10-05 实测，R9-B 干净树 `0e38b018b24b9ba0aa358f8d26a7f012`／32796 行，直接 grep 非偏移换算）**：`if (true) {` 门控 = **`:17811`**（其上注释 `:17809`）⇒ 进入条件「无多层 break ∧ 无 do-while ∧ 无 switch ∧ 无 match ∧ 无递归调用 ∧ 无异常处理」= **`:17816`** ⇒ 记录 `code_len_before_structured` = `:17818` ⇒ `try self.tryGenerateStructuredControlFlowNew(...)` = **`:17824`** ⇒ 成功即 `return`（`:17825–:17827`）⇒ 失败回滚 `code.shrinkRetainingCapacity(...)` + 复位 `return_generated`/`break_generated` = **`:17829–:17831`**。上游：AST-Direct 门 **`:17771`** ⇒ `tryGenerateFromLabels` 调用 **`:17775`**，其失败分支 **`:17805–:17806`** 为 `return error.AstDirectGenerationFailed`（注释原文「不再回退到结构化路径/状态机」）⇒ **AST-Direct 一旦失败根本走不到本节结构化兜底**，本文「失败后回退状态机」的叙述只适用于 AST-Direct 门条件不满足（`has_do_while`/`has_switch`/`has_match`/多层 break/异常处理）的情形 ⇒ 该路径的可达性与 PERF-001 的「否决位放开」议题同源。正文 §代码定位 表的 `:17507`/`:17512`/`:17524–17528` 属 RC-5 代次读数，保留不改写。
**发现日期**: 2026-02-27

---

## 问题描述

结构化控制流生成器在循环中生成嵌套 if 语句时，错误地在第二个 if 的 then 分支中插入了 `continue`，导致后续代码被跳过。

## 复现代码

```php
<?php
$x = "a";
for ($i = 0; $i < 2; $i++) {
    if ($i == 0) {
        $x = "b";
    }
    if ($i == 1) {
        $x = "c";
    }
}
echo $x . "\n";
// 期望: c
// 实际: b
?>
```

## 生成的代码（错误）

```zig
while (true) {
    if ($i == 0) {
        reg_21 = "b";
        if ($i == 1) {  // 第二个 if 嵌套在第一个 if 中！
            reg_22 = "c";
            continue;  // 错误：跳过了后续代码
        } else {
            reg_22 = reg_21;
        }
    } else {
        reg_21 = reg_23;  // 永远不会执行
    }
    reg_23 = reg_22;
}
```

## 期望的代码

```zig
while (true) {
    if ($i == 0) {
        reg_21 = "b";
    } else {
        reg_21 = reg_23;
    }
    
    if ($i == 1) {  // 顺序的，不是嵌套的
        reg_22 = "c";
    } else {
        reg_22 = reg_21;
    }
    
    reg_23 = reg_22;
}
```

## 根本原因

结构化控制流生成器（`tryGenerateStructuredControlFlowNew`）在重建控制流时：
1. 错误地将两个顺序的 if 语句识别为嵌套结构
2. 在第二个 if 的 then 分支中插入 `continue`，认为这是循环的最后一条语句
3. 导致第一个 if 的 else 分支永远不会执行

## 影响范围

- 循环中有多个顺序的 if 语句
- 结构化控制流生成模式（非状态机模式）

## 临时解决方案

禁用结构化控制流生成，强制使用状态机模式：

```zig
// src/aot/native_linker.zig:2375
if (false) {  // 禁用结构化控制流
    const structured_result = try self.tryGenerateStructuredControlFlowNew(&writer, func, cleanup_regs, alloca_regs);
    if (structured_result) {
        return;
    }
}
```

> **该手段已作废**（保留原文以便追溯）。当前代码同一门控写作 `if (true)`，结构化控制流路径**处于启用状态**，只是外面套了一圈「失败即回滚」。

### 修复落地（2026-10-01 取证，`src/aot/native_linker.zig`）

| 锚点 | 当前行 | 内容 |
|---|---|---|
| 结构化路径门控 | :17507 `if (true)`（原登记 :17362） | 上方注释 :17505 `// 结构化控制流生成（AOT-CODEGEN-002 已修复）`；进入条件为「无多层 break、无 do-while、无 switch/match、无递归调用、无异常处理」（:17512） |
| 失败回滚 | :17514 / :17524–17528（原登记 :17369 / :17379-17383） | 记录 `code_len_before_structured`，结构化返回 false 时 `shrinkRetainingCapacity` 截断并复位 `return_generated`/`break_generated` ⇒ 结构化生成失败不再留下半成品，交状态机兜底 |
| `isMergeBlock` | :27193（结构化路径内的嵌套辅助函数；原登记 :26997） | **前驱数 >1 即判定为合并块** —— 这是「顺序 if 被误认成嵌套」的正解：两个顺序兄弟 `if` 的 merge 块正是有多前驱的块 |
| br 目标为合并块 | :27392–27397（原登记 :27196-27201） | 命中时**只发来自当前块的 Phi 赋值后 `return`**，合并块本体交由 `cond_br` 处理器在 if/else 之后统一处理 ⇒ 不再把第二个 `if` 内联进第一个 `if` 的 then 臂，也不再插入吞掉后续语句的 `continue` |
| DFS 不跟随合并块 | :27474–27479（原登记 :27279-27283） | `loop_.blocks.contains(target)` 且 `isMergeBlock` ⇒ 直接 `return` 不递归；例外是嵌套循环退出块（`target_is_nested_exit`，:27391）仍需正常处理 |

> **行号口径（2026-10-03 重新 grep）**：上表为当前工作区树（`0ff09cf` + RC-5 未提交 +54）实测行号；原登记值基于 `b21cdfd`（32296 行，现为 32492 行），≥:934 段因 RC-4 首块 +14、≥:15265 段 +145、≥:25283 段再 +51（RC-5 注释+例程）。

配套修复（同一处代码注释登记）：**AOT-PHI-001** 放宽「target 必须在 `loop_.blocks` 中」的要求（:27395–27396，原登记 :27199-27200），使 if/else 的 merge 块虽不在循环块集合内、但在循环体内时同样能拿到 PHI 赋值。

## 修复方案

### 方案 1: 修复结构化控制流生成器

在 `tryGenerateStructuredControlFlowNew` 中：
1. 正确识别顺序的 if 语句（不是嵌套的）
2. 不要在非最后一条语句的 if 分支中插入 `continue`
3. 改进控制流重建算法

### 方案 2: 改进状态机代码生成

状态机模式虽然正确，但生成的代码冗长。可以优化：
1. 识别简单的控制流模式
2. 生成更简洁的代码
3. 减少不必要的状态转换

### 推荐方案

> **2026-10-01 回溯**：短期手段（禁用结构化控制流）已作废；实际采纳**方案 1**（在结构化生成器内做 merge 块判定，见 §修复落地），并把结构化路径重新启用 + 失败回滚。方案 2（优化状态机）未做，状态机仅作为结构化失败时的兜底路径存在。

短期：使用方案 1 的临时解决方案（禁用结构化控制流）  
长期：重构结构化控制流生成器，参考 LLVM 的 StructurizeCFG pass

## 相关代码

> 工单原文的 `:2375 / :5700 / :2330` 是 2026-02 的文件几何，早已漂移。以下为 **2026-10-03 重新 grep 的当前工作区树锚点**（`src/aot/native_linker.zig`，现 **32492** 行；2026-10-01 那次实测基于 `b21cdfd` 的 32296 行，括号内保留原值）：

- `src/aot/native_linker.zig:17397` — `generateControlFlowStateMachine`（兜底路径；原 :17252）
- `src/aot/native_linker.zig:17507` — 结构化控制流路径门控（现 `if (true)`，回滚在 :17524–17528；原 :17362 / :17379-17383）
- `src/aot/native_linker.zig:24574` — `tryGenerateStructuredControlFlowNew`（原 :24429）
- `src/aot/native_linker.zig:27193` — `isMergeBlock`（前驱 >1 判定；原 :26997）
- `src/aot/native_linker.zig:27392` / `:27475` — 本工单两处修复点（原 :27196 / :27279）

## 测试用例

> 下面的 here-doc 是 2026-02 的临时手段，**已固化**为永久探针 `fuzzy_scripts_720/tmp/c005_k_seq_if_for_tmp.php`（勿删；后续复测一律走项目内探针，不再往 `/tmp` 造散脚本）。当前树复测命令与实测读数：
>
> ```bash
> cd /Users/wangjianjun/products/parser
> timeout 10 /opt/homebrew/bin/php fuzzy_scripts_720/tmp/c005_k_seq_if_for_tmp.php   # K x=c
> timeout 300 ./zig-out/bin/php-interpreter --compile --no-debug-info \
>   --output=/tmp/aot_compile_c005_k_seq_if_for_tmp fuzzy_scripts_720/tmp/c005_k_seq_if_for_tmp.php
> timeout 10 /tmp/aot_compile_c005_k_seq_if_for_tmp                                   # K x=c，RUN_RC=0
> rm -f /tmp/aot_compile_c005_k_seq_if_for_tmp
> ```

```php
<?php
$x = "a";
for ($i = 0; $i < 2; $i++) {
    if ($i == 0) {
        $x = "b";
    }
    if ($i == 1) {
        $x = "c";
    }
}
echo $x . "\n";
?>
```

```bash
# 期望输出: c
# 实际输出: b   ← 2026-02 的历史读数；当前树实测为 c（见上）
```

---

**更新日志**:
- 2026-10-01: **状态 已识别 → CLOSED**。本工单正文从未登记收口，但代码侧真修早已落地并留痕（`:17360` 注释「AOT-CODEGEN-002 已修复」+ 两处修复点 :27196/:27279）；本轮补齐取证：结构化路径已由 `if (false)` 改回 `if (true)`（:17362）并带失败回滚（:17379-17383）、`isMergeBlock` 前驱 >1 判定（:26997）、br 命中合并块只发 PHI 不内联（:27196-27201）、DFS 不递归跟随合并块（:27279-27283）；复测原文复现（永久探针 `c005_k_seq_if_for_tmp.php`）**`K x=c` 与 PHP 逐字节等值**。同轮换掉 2026-02 的过期行号、作废 here-doc 散脚本手段
- 2026-02-27: 初始创建，问题识别和分析
