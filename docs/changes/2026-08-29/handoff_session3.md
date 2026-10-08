# 交接文档（会话 3）：f085 单语句 if-continue/if-break 修复 + f087 嵌套短路链诊断与修复

> 日期：2026-08-29 | 涉及文件：`src/aot/native_linker.zig`
> 当前 HEAD：`64eccbc`（已提交，仅含 f085 修复）
> 上级交接链：
> - `docs/changes/2026-08-29/handoff.md`（会话 1：f028 闭环）
> - `docs/changes/2026-08-29/handoff_session2.md`（会话 2：短路链与 if-without-else 六组修复）

---

## 1. TL;DR

本会话完成了交接文档 §6 中的 **f085 单语句 if-continue 缺陷**修复，并额外修复了同家族 **if-break 单语句**变体。提交 `64eccbc`（+171/-4）。全量回归 **PASS=80 FAIL=28**（与上轮一致），f085 由 FAIL_RUNTIME/FAIL_DIFF 转 **PASS**，**零新增**。

随后攻坚 **f087 RBAC 权限检查** FAIL_DIFF，定位根因为 **嵌套 `||` 在 `&&` rhs 中的 `logical_rhs_` 块发射遗漏**——`generateLabelDrivenBlockRange` 在处理嵌套短路链时跳过了内层 `||` 的 rhs 块。进行了两轮修复：
1. 在普通线性块 cond_br case 的 then 块嵌套 cond_br 中增加短路链检测（7676行）
2. 在 foreach body cond_br 的 then 块嵌套 cond_br 中增加 `nested_end` 范围扩大（9205行）

**当前状态**：`repro_f087h.php`（最简复现，顶层 if）已修复。`repro_f087k.php`（foreach 循环内嵌套）仍有问题——PHI 消解中 `incoming.block` 匹配不正确。全量回归测试运行中。

---

## 2. f085/if-break 修复清单（提交 `64eccbc`）

| # | 修复 | 位置（foreach/for/while 各一处） | 归因 |
|---|------|------|------|
| 1 | `merge_bi` fallback 条件增加 `!then_is_be`/`!then_is_back_edge` | ~9208 / ~10904 / ~12202 | then 是回边时，else 是循环体延续而非 merge，不应设 merge_bi |
| 2 | 同条件增加 `then_bi == cleanup_idx/exit_idx` 守卫 | 同上 | then 是 break 目标时同理 |
| 3 | `else_is_be` 路径增加 `then_is_break` 检测 | ~9290（foreach）/ ~10976（for） | then 是 break 目标时生成 `break + PHI 物化` |
| 4 | 移除会话 2 遗留诊断探针 | ~9258 | 探针清理 |

---

## 3. f087 嵌套短路链修复（未提交，working tree）

### 3.1 症状

`f087_rbac_abac_policy_inheritance.php` 的 RBAC 权限检查返回 `false`（应为 `true`）。根因在 `hasPermission` 方法第 29 行：

```php
if (($p->resource === $resource || $p->resource === '*') && ($p->action === $action || $p->action === '*')) return true;
```

内联嵌套 `(||) && (||)` 在 AOT 中条件判为 false。用变量拆分后正常——**仅内联在 if 条件中时复现**。

### 3.2 最简复现

`fuzzy_scripts_720/tmp/repro_f087h.php`（顶层 if，已修复）：

```php
if (($r === $resource || $r === '*') && ($r === $resource || $r === '*')) {
    echo "true\n";
} else {
    echo "false\n";
}
```

`fuzzy_scripts_720/tmp/repro_f087k.php`（foreach 循环内，仍有问题）：

```php
class Role {
    public function hasPermission(string $resource, string $action): bool {
        foreach ($this->permissions as $p) {
            if (($p->resource === $resource || $p->resource === '*') && ($p->action === $action || $p->action === '*')) return true;
        }
        return false;
    }
}
```

### 3.3 根因分析

**第一层问题（已修复）**：`generateLabelDrivenBlockRange` 的普通线性块 cond_br case 中，then 块有嵌套 cond_br 时，out-of-order 路径不处理嵌套短路链的 PHI 消解和 br 终止符。

**修复**：在 7676 行增加 `sc_then_is_and`/`sc_then_is_or` 检测，当 then/else 块是 `logical_merge_` 时走短路链专用处理（类似 else 块的 8126-8197 行逻辑）。

**第二层问题（部分修复）**：`generateForeachFromLabels` 的 body cond_br 处理中，then 块有嵌套 cond_br 时，`nested_end` 搜索逻辑对短路链不正确——`logical_merge_` 块的 cond_br 终止符不被搜索。

**修复**：在 9205 行增加 `nested_sc_is_and`/`nested_sc_is_or` 检测，扩大 `nested_end` 范围到包含整个短路链。

**遗留问题**：PHI 消解中 `incoming.block == then_blk` 不匹配——`logical_merge_8` 的 PHI incoming 来自 `logical_merge_6` 和 `logical_merge_10`，而非 `then_blk`（`logical_rhs_7`）。需要修改 PHI incoming 匹配逻辑。

### 3.4 IR 结构（repro_f087k）

```text
foreach_body_1:
  reg_18 = identical(reg_16, reg_17)               // $p->resource === $resource
  br reg_18, logical_merge_6, logical_rhs_5         // 第一个 || 的 cond_br
logical_rhs_5:                                      // 第一个 || 的 rhs
  reg_22 = identical(reg_20, reg_21)                // $p->resource === '*'
  br logical_merge_6
logical_merge_6:                                     // 第一个 || 的 merge
  reg_23 = phi [reg_18, foreach_body_1], [reg_22, logical_rhs_5]
  reg_24 = const.bool false                          // && 的 false_val
  br reg_23, logical_rhs_7, logical_merge_8         // && 的 cond_br
logical_rhs_7:                                       // && 的 rhs（第二个 ||）
  reg_28 = identical(reg_26, reg_27)                // $p->action === $action
  br reg_28, logical_merge_10, logical_rhs_9       // 第二个 || 的 cond_br
logical_merge_8:                                     // && 的 merge ← PHI 消解失败！
  reg_34 = phi [reg_24, logical_merge_6], [reg_33, logical_merge_10]
  br reg_34, if_then_11, foreach_increment_2
logical_rhs_9:                                       // 第二个 || 的 rhs
  reg_32 = identical(reg_30, reg_31)                // $p->action === '*'
  br logical_merge_5
logical_merge_10:                                    // 第二个 || 的 merge
  reg_33 = phi [reg_28, logical_rhs_7], [reg_32, logical_rhs_9]
  br logical_merge_8
```

### 3.5 下一步

1. 修改 then 块嵌套 cond_br 的短路链 PHI 消解：`incoming.block` 应匹配 `nested_cb.then_block`/`nested_cb.else_block`（短路链的 merge/rhs 块），而非 `then_blk`（cond_br 所在块）。
2. 或者改为匹配 `sc_merge_blk` 的 PHI incoming 中来自短路链路径的块（即排除来自外层 `&&` 的 false 路径的块）。
3. 同步 for/while 生成器中的相同逻辑。

---

## 4. 复现脚本清单（本会话新增）

| 脚本 | 覆盖缺陷 | 状态 |
|------|----------|------|
| `repro_sc_break_single.php` | foreach if-break 单语句 | 通过 |
| `repro_sc_for_break.php` | for if-break 单语句 | 通过 |
| `repro_f087.php` ~ `repro_f087m.php` | f087 嵌套短路链 | 诊断中 |

---

## 5. 遗留问题 / 待办

| 优先级 | 事项 |
|--------|------|
| **P0** | §3.5：f087 foreach 内嵌套短路链 PHI 消解 incoming 匹配修复 |
| P1 | while 生成器的 `else_is_back_edge` 路径未同步 `then_is_break` 检测 |
| P1 | for/while 生成器中的嵌套短路链检测同步 |
| P2 | 其余 28 条基线失败逐个攻坚 |
