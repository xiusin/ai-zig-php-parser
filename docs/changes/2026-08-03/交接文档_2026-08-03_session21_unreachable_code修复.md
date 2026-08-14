# 交接文档：Session 21 — unreachable code 修复（f044/f104/f105/f177）

> **日期**：2026-08-03
> **会话 ID**：d3a38fbd-70b1-4f00-9da2-0ffca6359f97
> **承接**：Session 20（PHI retain 修复后暴露的 unreachable code 编译错误）

---

## 一、TL;DR

本会话重点修复 PHI retain 修复后暴露的 **unreachable code** 编译错误（f044/f104/f105/f177），并对 foreach/for/while 三种循环的代码生成路径做了多层防御性修复。核心成果：

- **f177 已修复**：通过 `else_branch_start` 范围限制 + cond 块标记 + `return_generated` 检查解决。
- **f044/f104/f105 仍未完全修复**：根因已定位到 `lastLineIsReturn` 检查未生效，需要进一步调试。
- **全量回归测试尚未完成**：之前的测试因 macOS 无 `timeout` 命令导致全部 FAIL，修复后重新运行的结果为 **1 PASS / 63 FAIL**（严重退化），随后回退了 `else_branch_start` 修改但 `lastLineIsReturn` 仍未解决。

---

## 二、已完成的修改

### 2.1 `else_branch_start` 范围限制（L6614）

**文件**：`src/aot/native_linker.zig`

在 `generateLabelDrivenBlockRange` 的 cond_br then 分支 `.br` 子 case 中，计算 else 分支的起始位置（else 块的 br 目标），限制递归调用范围以排除 else 分支的块：

```zig
var else_branch_start: ?usize = null;
if (else_bi) |ei| {
    const else_blk = func.blocks.items[ei];
    if (else_blk.terminator) |et| {
        if (et == .br) {
            for (0..func.blocks.items.len) |idx| {
                if (func.blocks.items[idx] == et.br) {
                    else_branch_start = idx;
                    break;
                }
            }
        }
    }
}
const then_end = end_idx;  // 注意：最终回退为 end_idx，else_branch_start 未生效
```

> **状态**：`else_branch_start` 计算保留但 `then_end` 最终设为 `end_idx`（不限制范围），因为限制范围导致大量回归。需要找到更精确的限制方式。

### 2.2 cond 块标记为已处理（L7329, L8381, L9121）

在 `generateForeachFromLabels`、`generateForFromLabels`、`generateWhileFromLabels` 中，在生成循环代码前将 cond 块标记为已处理，防止主循环在 cond_br case 处理完 then/else 分支后再次遇到此循环 cond 块并重复生成循环代码：

```zig
try processed.put(cond_idx, {});
```

### 2.3 `return_generated`/`break_generated` 检查（L7911, L7941, L8931, L8982, L9630）

在 foreach/for/while 的 cond_br case 末尾递归调用 `generateLabelDrivenBlockRange` 前，添加 `return_generated`/`break_generated` 检查：

```zig
if (!self.return_generated and !self.break_generated) {
    try self.generateLabelDrivenBlockRange(writer, func, body_idx + 1, last_back_edge + 1, ...);
}
```

### 2.4 `loop_end` 范围限制（L7488-7505, L8533-8548, L9280-9295）

在 foreach/for/while 的 cond_br case 开始时，预计算循环最后回边位置 `loop_last_be`，生成 `loop_end = @min(end_idx, loop_last_be + 1)`，并将 cond_br 内部的递归调用范围从 `end_idx` 替换为 `loop_end`：

```zig
var loop_last_be: usize = if (increment_idx) |inc_idx| inc_idx else body_idx;
for (body_idx + 1..func.blocks.items.len) |blk_i| {
    const blk = func.blocks.items[blk_i];
    if (blk.terminator) |t| {
        if (t == .br and (t.br == cond_block_ptr or t.br == inc_block_ptr)) {
            loop_last_be = blk_i;
        }
        if (t == .cond_br) {
            if (t.cond_br.then_block == cond_block_ptr or t.cond_br.then_block == inc_block_ptr or
                t.cond_br.else_block == cond_block_ptr or t.cond_br.else_block == inc_block_ptr)
            {
                loop_last_be = blk_i;
            }
        }
    }
}
const loop_end = @min(end_idx, loop_last_be + 1);
```

所有 `generateLabelDrivenBlockRange` 调用中的 `end_idx` 替换为 `loop_end`（仅限 foreach/for/while 的 cond_br case 内部）。

### 2.5 `generateIfFromLabels` merge 块重复处理检查（L10139）

在 `generateIfFromLabels` 处理 merge 块前，检查是否已被标记为已处理：

```zig
if (processed.contains(merge_idx)) return merge_idx;
```

### 2.6 `lastLineIsReturn` 检查（L7948, L7958, L8987, L8999, L9707）

在 foreach/for/while 的 increment 指令生成和 PHI 消解前，添加 `lastLineIsReturn` 检查：

```zig
if (!self.return_generated and !self.break_generated and !self.lastLineIsReturn(writer)) {
    // 生成 increment / PHI
}
```

> **状态**：`lastLineIsReturn` 检查未生效，f044 仍然失败。原因待查。

---

## 三、在进行中的任务

### 3.1 f044/f104/f105 unreachable code 修复（P0，未完成）

**根因**：foreach 循环 body 内的 cond_br 的 then 分支通过递归调用处理了 `.ret` 块（函数级 return），`return_generated` 被设为 `true`，但 cond_br 的 merge 逻辑用 AND 合并 then/else 返回状态后将其重置为 `false`，导致后续 increment/PHI/continue 代码被错误生成（unreachable code）。

**已尝试的修复**：
1. `else_branch_start` 范围限制 → 导致大量回归，已回退
2. `return_generated`/`break_generated` 检查 → 未完全生效
3. `loop_end` 范围限制 → 减少了越界处理但未完全解决
4. `lastLineIsReturn` 检查 → **未生效**，需要调试

**下一步**：
- 调试 `lastLineIsReturn` 为什么没有检测到 return 语句。可能原因：
  - `return error.RuntimeError` 不是以 `"return "` 开头？不对，它是以 `"return "` 开头的。
  - writer 在递归调用后可能有其他输出覆盖了 return 行？
  - `self.return_generated` 在 cond_br merge 逻辑中被重置为 `false`，但 `lastLineIsReturn` 检查的是 writer 内容，不是 `return_generated`。
- 检查生成的 Zig 代码中 `return runtime.Value.initNull()` 后面的行是否确实是最后写入的行。
- 考虑替代方案：在 cond_br merge 逻辑中，如果 then 分支的 `loop_body_return_generated` 为 true，则不重置 `return_generated`。

### 3.2 全量回归测试（P0，未完成）

之前的回归测试因 macOS 无 `timeout` 命令导致全部 FAIL。修复后的测试结果为 **1 PASS / 63 FAIL**（51 DIFF + 9 RUN + 3 COMPILE）。需要：
- 重新编译（已包含 `lastLineIsReturn` 修复）
- 重新运行全量回归测试
- 分析 FAIL_DIFF 的根因

### 3.3 f026 SIGBUS 调查（P0，未开始）

f026 在之前的测试中报告 SIGBUS (exit=133)，尚未调查。

### 3.4 变更文档更新（P1，未开始）

需要更新 `docs/changes/2026-08-01/unreachable_code_else_branch_start_a3b2c1.md`，记录本会话的所有修改。

---

## 四、已知问题

### 4.1 `lastLineIsReturn` 未生效

`lastLineIsReturn` 函数检查 writer 输出的最后一个非空行是否以 `"return "` / `"continue "` / `"break "` 开头。但在 f044 中，生成的代码确实以 `return runtime.Value.initNull();` 结尾，但 `lastLineIsReturn` 仍然返回 `false`。

**可能原因**：
1. writer 是 `ArrayListWriter`，`writer.list.items` 可能不是最终输出内容。
2. 在 cond_br merge 逻辑和 increment 生成之间，可能有其他代码写入了 writer。
3. `self.return_generated` 在 cond_br merge 逻辑中被重置为 `false`，但 `lastLineIsReturn` 检查的是 writer 内容，不是 `return_generated`。

### 4.2 `else_branch_start` 限制导致大量回归

当 `then_end = @min(end_idx, es)` 时，如果 `else_branch_start < blk_i`（IR 块排序交错），则 `then_end < blk_i`，递归调用范围为空，导致大量块未被处理。已回退为 `then_end = end_idx`。

### 4.3 `loop_end` 替换遗漏

在 foreach/for/while 的 cond_br case 中，部分 `generateLabelDrivenBlockRange` 调用仍使用 `end_idx` 而非 `loop_end`（如 `.cond_br` 子 case 中 `ti + 1, end_idx` 的调用）。需要确认这些调用是否也需要替换。

---

## 五、核心变更文件清单

| 文件 | 修改行 | 变更描述 |
|------|--------|---------|
| `src/aot/native_linker.zig` | L6614 | `else_branch_start` 计算（最终 `then_end = end_idx`） |
| `src/aot/native_linker.zig` | L7329 | foreach cond 块标记为已处理 |
| `src/aot/native_linker.zig` | L7488-7505 | foreach `loop_end` 预计算 |
| `src/aot/native_linker.zig` | L7602, L7634, L7770, L7842, L7868 | foreach cond_br 内 `end_idx` → `loop_end` |
| `src/aot/native_linker.zig` | L7911, L7941 | foreach `return_generated` 检查 |
| `src/aot/native_linker.zig` | L7948, L7958 | foreach `lastLineIsReturn` 检查 |
| `src/aot/native_linker.zig` | L8381 | for cond 块标记为已处理 |
| `src/aot/native_linker.zig` | L8533-8548 | for `loop_end` 预计算 |
| `src/aot/native_linker.zig` | L8625, L8653, L8789, L8861, L8887 | for cond_br 内 `end_idx` → `loop_end` |
| `src/aot/native_linker.zig` | L8931, L8982 | for `return_generated` 检查 |
| `src/aot/native_linker.zig` | L8987, L8999 | for `lastLineIsReturn` 检查 |
| `src/aot/native_linker.zig` | L9121 | while cond 块标记为已处理 |
| `src/aot/native_linker.zig` | L9280-9295 | while `loop_end` 预计算 |
| `src/aot/native_linker.zig` | L9367, L9505, L9558, L9595 | while cond_br 内 `end_idx` → `loop_end` |
| `src/aot/native_linker.zig` | L9630 | while `return_generated` 检查 |
| `src/aot/native_linker.zig` | L9707 | while `lastLineIsReturn` 检查 |
| `src/aot/native_linker.zig` | L10139 | `generateIfFromLabels` merge 块 `processed` 检查 |

---

## 六、后续开发建议

| 优先级 | 影响面 | 落地成本 | 建议 |
|--------|--------|----------|------|
| P0 | f044/f104/f105 编译失败 | 低 | 调试 `lastLineIsReturn` 未生效的原因：在 increment 生成前添加调试输出，确认 writer 内容和 `return_generated` 状态 |
| P0 | 全量回归测试 | 低 | 重新编译后运行全量回归测试，确认修改未引入退化 |
| P0 | f026 SIGBUS | 中 | 调查 f026 SIGBUS (exit=133) 的根因 |
| P1 | `else_branch_start` 精确限制 | 中 | 当 `else_branch_start < blk_i` 时不限制范围（当前已回退为 `end_idx`），需要更精确的范围计算 |
| P1 | cond_br merge 逻辑重构 | 高 | cond_br 的 then/else 返回状态合并逻辑（AND）过于简单，无法正确处理"then 分支 return、else 分支可达"的场景。考虑使用 `loop_body_return_generated` 替代 `return_generated` 来控制 increment/PHI 生成 |
| P2 | IR 块排序优化 | 高 | 根本原因是 IR 生成器将 then/else 分支块交错排列，线性处理逻辑无法正确处理。考虑在 IR 生成阶段对块进行拓扑排序，或重构代码生成器为基于 CFG 的递归处理 |
