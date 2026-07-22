# AOT 修复：generateStandardForLoop 中 if/else 的 return_generated 未重置导致循环变量不递增

**提交哈希**: `e9985bc`
**日期**: 2026-07-22
**影响级别**: P0（关键 — 影响 ReleaseFast 模式下 2 个脚本运行时正确性）

---

## 1. 高层摘要（TL;DR）

`generateStandardForLoop` 的 `go` 函数在处理 `cond_br`（if/else）时，`then` 块中的 `return` 语句设置 `self.return_generated = true`，但进入 `else` 块前未重置该标志。导致 `else` 块中的 `emitIncAndPhi` 跳过 PHI 更新（`if (self_.return_generated) return;`），循环变量不递增，形成无限循环。

**修复**：在 `then` 块生成后、`else` 块生成前添加 `self_.return_generated = false;` 重置，与 `generateCondBrBlock` 中的模式一致。

---

## 2. 影响范围

| 维度 | 说明 |
|------|------|
| 影响模式 | AOT ReleaseFast/ReleaseSafe 编译模式 |
| 影响场景 | `for` 循环内包含 `if (!cond) return;` 模式的 PHP 脚本 |
| 影响脚本数 | 修复 f081 和 f171 两个挂起问题 |
| Debug 模式 | 不受影响 |

### 修复前后对比

| 脚本 | 修复前 | 修复后 | 根因 |
|------|--------|--------|------|
| `f171_state_machine_dfa.php` | 超时 (exit=124) | ✅ PASS | `for` 内 `if (!isset(...)) return false;` 导致 PHI 跳过 |
| `f081_bplustree_index_range_query.php` | 超时 (exit=124) | ✅ PASS | 同上模式（B+Tree rangeQuery 方法内） |

---

## 3. 核心变更

| 文件 | 变更类型 | 变更内容 |
|------|----------|----------|
| `src/aot/native_linker.zig` | 修复 | `generateStandardForLoop.go` 函数 `cond_br` 处理中，`then` 块后、`else` 块前添加 `return_generated = false` |

### 变更代码

**位置**：`generateStandardForLoop` → `generateLoopBodyFromBlock.go` → `cond_br` case → `else` 分支（非 `cond_controls_loop`/`nested_loop` 的普通 if/else）

```zig
// 修复前：then 块可能有 return 设置 return_generated=true，
// 但 else 块中的 emitIncAndPhi 会因此跳过 PHI 更新

// 修复后：
} else if (loop_.blocks.contains(then_target)) {
    try go(self_, writer_, code_, func_, loop_, phi_updates_, then_target, visited, depth + 1, block_idx, nested_loop_exit_);
}

// 重置 return_generated 标志：then 块可能有 return，但 else 块仍需正常生成
// 否则 emitIncAndPhi 会因 return_generated=true 跳过 PHI 更新，导致循环变量不递增
self_.return_generated = false;

if (else_is_merge) {
    ...
```

---

## 4. 可视化概览

```mermaid
graph TD
    A["for ($i=0; $i<strlen($s); $i++)"] --> B["while (true) {"]
    B --> C["if (!cond) break;"]
    C --> D["if (!isset(...)) return false;"]
    
    D -->|then: return| E["return_generated = true"]
    D -->|else: 循环体| F["emitIncAndPhi()"]
    
    F -->|修复前| G{"return_generated?"}
    G -->|true| H["跳过 PHI 更新 ⚠️"]
    H --> I["reg_i 不递增 → 无限循环"]
    
    F -->|修复后| J{"return_generated?"}
    J -->|false (已重置)| K["正常生成 PHI 更新 ✅"]
    K --> L["reg_i = reg_i + 1 → 循环正常"]
```

---

## 5. 详细变更分析

### 5.1 Bug 机制

1. PHP 代码模式 `for (...) { if (!cond) return; ... }` 在 IR 中生成 `cond_br` 指令
2. `generateStandardForLoop.go` 处理 `cond_br` 时生成 `if (cond) { then } else { else }`
3. `then` 块中的 `return` 调用 `generateReturnInBlock`，设置 `self.return_generated = true`
4. `else` 块中调用 `emitIncAndPhi` 生成循环增量和 PHI 更新
5. `emitIncAndPhi` 检查 `if (self_.return_generated) return;` → **跳过 PHI 更新**
6. 循环变量 `reg_i` 不递增 → 条件 `i < strlen($s)` 永远为 true → **无限循环**

### 5.2 同类问题

`generateCondBrBlock` 函数在 line 13179-13180 已有相同的重置逻辑：
```zig
// 重置 return_generated 标志：then 块可能有 return，但 else 块仍需正常生成
self.return_generated = false;
```

但 `generateStandardForLoop.go` 中的独立 `if/else` 生成路径缺少此重置。本次修复补齐了这一遗漏。

---

## 6. 影响与风险评估

### 是否破坏式变更

**否**。仅添加一行 `self_.return_generated = false;`，与已有的 `generateCondBrBlock` 模式一致。

### 变更影响范围

| 范围 | 影响 |
|------|------|
| `for` 循环内含 `if (!cond) return;` 的代码 | 修复 — PHI 更新不再被跳过 |
| `for` 循环内不含 `return` 的 `if` 语句 | 无影响 — `return_generated` 本就为 false |
| `foreach` 循环（使用 `generateWhileLoopStructuredNew`） | 无影响 — 不经过此代码路径 |

### 全量回归结果

```
TOTAL:        61
PASS:         58  (从 56 → 58, +2)
FAIL_RUNTIME: 0   (从 2 → 0, 全部修复!)
FAIL_DIFF:    2   (f070, f090 — 独立正确性问题，与本次修复无关)
SKIP:         1   (f004 — PHP 错误)
```

---

## 7. 遗留问题

| 编号 | 问题 | 优先级 | 说明 |
|------|------|--------|------|
| 1 | `f070_event_sourcing_cqrs_snapshot.php` 输出差异 | P2 | 投影值不正确（balance/tx_count 不对），独立正确性问题 |
| 2 | `f090_promise_future_async_concurrent.php` 输出差异 | P2 | Promise.all 聚合结果不正确，独立正确性问题 |

---

## 8. 后续开发/优化建议

| 优先级 | 建议 | 影响面 | 落地成本 |
|--------|------|--------|----------|
| P1 | 审查 `generateStandardForLoop.go` 中所有 `cond_br` 分支路径，确保 `return_generated` 一致重置 | 高 | 低 |
| P2 | 调查 f070 的 `foreach` + `if/elseif` 事件回放输出差异 | 中 | 中 |
| P2 | 调查 f090 的 Promise.all 聚合输出差异 | 中 | 中 |
| P3 | 统一 `generateStandardForLoop.go` 和 `generateCondBrBlock` 的 if/else 生成逻辑 | 低 | 高 |
