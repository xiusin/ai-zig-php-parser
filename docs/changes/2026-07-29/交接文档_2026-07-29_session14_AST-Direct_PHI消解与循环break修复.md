# 交接文档：Session 13-14 AST-Direct PHI 消解与循环 break 修复

**日期**：2026-07-29  
**范围**：`src/aot/native_linker.zig` — AST-Direct 代码生成路径  
**状态**：foreach+break TypeError 已修复，if/else 合并点 PHI 消解问题已定位但未完全修复

---

## 一、TL;DR

本轮工作跨 Session 13-14，系统性修复 AST-Direct 代码生成中的 **foreach + break + PHI 消解缺陷**（导致 TypeError exit=255）和 **for 循环回边处理**问题。**f057 的 TypeError 已消除**，但 AOT 执行路径仍不完整（仅遍历 3 个节点而非 7 个），根因已定位到 **if/else 合并点 PHI 未正确消解**（`if_merge_4` 块的指令被错误地放入 else 分支，且 ternary PHI `reg_44` 未被赋值）。

---

## 二、当前状态

| 指标 | Session 12 交接时 | 当前 | 变化 |
|------|-------------------|------|------|
| PASS | 5 | 6 | +1 |
| FAIL_COMPILE | 0 | 0 | 0 |
| FAIL_RUNTIME | 46 | 43 | -3 |
| FAIL_DIFF | 15 | 17 | +2 |
| SKIP | 1 | 1 | 0 |
| **总计** | **67** | **67** | |

> 回归报告来自 `fuzzy_scripts_720/regression_report.md`（2026-07-27 23:40:59 生成），本次 PHI 修复尚未跑完整回归测试验证最新效果。

### TypeError 脚本状态

| 脚本 | 修复前 | 当前 | 根因 |
|------|--------|------|------|
| **f057** | TypeError exit=255 | ✅ 无 TypeError，但执行路径不完整 | foreach+break PHI 已修复；if/else 合并点 PHI 未完全修复 |
| **f070** | TypeError exit=255 | ❌ 仍有 TypeError | `foreach() argument must be of type array\|object, null given`（属性初始化问题） |
| **f080** | TypeError exit=255 | ❌ 仍有 TypeError | `waitForLock(): Argument #1 ($waiter) must be of type int, null given`（coalesce `??` PHI 问题） |
| **f095** | TypeError exit=255 | ❌ 仍有 TypeError | `Cannot assign null to property IRInstruction::$args` |
| **f110** | - | ✅ 输出匹配 | - |
| **f163** | - | ✅ 输出匹配 | - |

---

## 三、已完成任务

### 1. foreach + break PHI 消解修复（核心修复）

**问题**：`foreach` 循环中 `break` 时，与 break 路径相关的 PHI 节点未正确赋值，导致后续变量为 `null`，触发 TypeError。

**修复方案**：

#### 1.1 新增 `generateExitPHIAssignments` 函数

```zig
fn generateExitPHIAssignments(
    self: *Self, writer: anytype, func: *const IR.Function,
    source_idx: usize, target_idx: usize, indent: []const u8,
) !void {
    // 遍历目标块（cleanup/exit）的 PHI 指令
    // 查找来自源块的 incoming 值
    // 生成 reg_N = reg_M 赋值
}
```

**作用**：在 `break` 语句之前调用，将当前寄存器的值赋给目标块（cleanup/exit）的 PHI 结果寄存器。

#### 1.2 新增 `current_loop_cleanup_block` 字段

```zig
current_loop_cleanup_block: ?usize = null,
```

**作用**：跟踪 foreach 循环的 cleanup 块索引，用于检测 `break` 目标。

#### 1.3 新增 `isLoopBreakTarget` 和 `writeBrInLoopContext` 辅助函数

- `isLoopBreakTarget`：检查 br 目标块是否是当前循环的退出块（exit/cleanup）
- `writeBrInLoopContext`：在嵌套 if 的 then/else 块中处理 br 终止符，如果是循环退出块则生成 `break :label`，否则交给 `generateBrToMergeCondBr`

#### 1.4 在所有 `break` 位置前生成 PHI 赋值

修改了以下函数，在所有 `break :label` 之前调用 `generateExitPHIAssignments`：

- `generateLoopConditionChain`：6 处 break 点（条件链中的 `if (!cond) break` / `if (cond) break`）
- `generateForeachFromLabels`：body 块直接 break + then 块嵌套 break
- `writeBrInLoopContext`：嵌套 if 中 else 块的 break
- `generateIfFromLabels`：then 块嵌套 break

#### 1.5 for 循环回边处理优化

```zig
// 之前：br 到非 exit 块一律当作嵌套控制流递归处理
// 修复：先检查 br 到 cond/loop 块（回边），跳过递归处理
} else if (br_target == cond_block_ptr or br_target == loop_block_ptr) {
    // br 到 cond/loop 块：回边，不需要额外代码
}
```

**效果**：避免 for 循环 body 块正常 `br` 到 cond 块时被错误地递归处理。

### 2. throw 终止符处理

新增 `writeThrowTerminator` 函数，在 `generateIfFromLabels` 的 then 块处理中添加 `.throw` case：

```zig
.throw => |ex_reg| {
    try self.writeThrowTerminator(writer, ex_reg, cleanup_regs, then_indent);
},
```

### 3. f057 执行路径问题调查（深度分析）

通过创建 11 个最小化测试用例，逐步缩小问题范围：

| 测试文件 | 测试目标 | 结果 |
|----------|----------|------|
| `test_f057_min.php` | 最小化工作流引擎 | AOT 仅遍历 3 节点 |
| `test_rec.php` | 递归调用 + by-reference | ✅ 通过 |
| `test_rec2.php` | 简化递归 | ✅ 通过 |
| `test_rec3.php` | by-reference + array_key_exists | ❌ AOT 输出不完整 |
| `test_ternary.php` | 三元运算符 | ✅ 通过 |
| `test_ref_arr.php` | by-reference 数组修改 | ✅ 通过 |
| `test_concat.php` | 字符串拼接 | ✅ 通过 |
| `test_3level.php` | 3 层 by-ref 链 | ✅ 通过 |
| `test_inarray.php` | in_array + array_key_exists + ternary | ❌ PHI `reg_44` 未赋值 |

**最终定位**：`test_inarray.php` 的 `level2` 函数中，`if ($found) { return; }` 后的代码 `echo "level2: ctx=" . json_encode($ctx) . "\n"` 中的 `json_encode` 调用和后续 ternary 的 PHI `reg_44` 未被正确赋值。

---

## 四、进行中/未完成任务

### 4.1 f057 执行路径不完整（P0，进行中）

**现象**：AOT 仅输出 `start → fetch → validate`，PHP 输出 `start → fetch → validate → process → notify → end → reject`。

**根因分析**（通过 IR dump 确认）：

IR 块结构：
```
ternary_merge_2:
  PHI reg_22
  concat reg_23
  echo reg_25
  br reg_14, if_then_3, if_merge_4    ← if ($found) 的 cond_br

if_then_3:
  echo "already visited"
  ret

if_merge_4:                            ← 同时是 if 的 merge 块和后续代码块
  const.string "level2: ctx="
  load $ctx
  call @json_encode(...)
  concat ...
  echo ...
  call @array_key_exists(...)
  br reg_36, ternary_then_5, ternary_else_6  ← 第二个 ternary 的 cond_br

ternary_then_5:
  const.string "yes"
  box ...
  br ternary_merge_7

ternary_else_6:
  const.string "no"
  box ...
  br ternary_merge_7

ternary_merge_7:
  PHI reg_44 = phi [reg_41, ternary_then_5], [reg_43, ternary_else_6]
  concat reg_45 = concat(reg_38, reg_44)
  ...
```

**问题 1**：`generateIfFromLabels` 处理 `if_then_3` → `if_merge_4` 时，`if_merge_4` 有 `cond_br` 终止符，函数返回 `merge_idx` 让主循环处理。但主循环处理 `if_merge_4` 时，`cond_br` case 生成了 if/else 结构，**else 块错误地包含了 `ternary_else_6` 的指令**（`reg_42 = "no"`），而非 `if_merge_4` 的指令（json_encode 等）。

**问题 2**：`ternary_merge_7` 的 PHI `reg_44` 未被消解，仅生成了注释 `// PHI: reg_44 (handled in terminator)`，导致后续 `php_concat(reg_38, reg_44, ...)` 使用未初始化值。

**修复方向**：
1. 确保 `if_merge_4` 的指令在主循环 `cond_br` case 中被完整生成（包括 json_encode 调用）
2. 确保 `ternary_merge_7` 的 PHI 在 ternary if/else 合并时被正确消解
3. 可能需要检查 `generateLabelDrivenBlockRange` 中 `cond_br` case 对 else 块的处理逻辑，确保 else 块是 IR 中的正确块而非其他块的指令

### 4.2 f080 coalesce TypeError（P1，待处理）

**现象**：`waitForLock(): Argument #1 ($waiter) must be of type int, null given`

**根因**：coalesce `??` 运算符的 PHI 消解问题。`??` 的 IR 结构是隐式 if/else，当左操作数为 null 时取右操作数。PHI 在合并点未正确消解，导致 `$waiter` 变量为 null。

### 4.3 f070 foreach null 问题（P1，待处理）

**现象**：`foreach() argument must be of type array|object, null given`

**根因**：属性初始化问题。对象的数组属性在 AOT 中未被正确初始化，导致 `foreach($this->state)` 时 `$this->state` 为 null。

### 4.4 编译验证与回归测试（P0，待执行）

本次修改 **尚未编译验证** 和 **尚未运行完整回归测试**。需要：
1. `timeout 120 zig build`
2. `bash scripts/regression_test_720.sh`

### 4.5 超时脚本和 FAIL_DIFF（P1，待处理）

17 个超时脚本（exit=142）和 17 个 FAIL_DIFF 脚本仍需处理，部分可能由 PHI 消解问题导致。

---

## 五、已知问题

### 5.1 early-exit 问题（P0，继承自 Session 12，仍未修复）

**根因**：`generateLabelDrivenBlockRange` 的 early-exit 行为

```zig
if (self.return_generated or self.break_generated) {
    for (i..end_idx) |j| {
        try processed.put(j, {});  // ← 标记所有剩余块为已处理
    }
    return;
}
```

**影响**：17+ 个 timeout 脚本，`||`/`&&` PHI 未消解导致条件永远 false → 无限循环。

**修复方向**：在 early-exit 中，不标记控制结构块（`if_then_`、`logical_merge_`、`logical_rhs_`）为已处理。

### 5.2 if/else 合并点 PHI 消解（P0，新发现）

**根因**：`generateLabelDrivenBlockRange` 的 `cond_br` case 在处理 `if_merge_` 块（既是 merge 又是后续代码块）时，else 块的指令来源不正确，且 ternary 的 PHI 未被消解。

**影响**：f057 执行路径不完整，可能影响其他包含 `if ($x) { return; }` 后跟表达式的脚本。

### 5.3 PHPString double free（P1，5 脚本，继承）

- 脚本：f025/f031/f072/f119/f160
- 根因：release 后 alloca 中的值变悬垂引用

### 5.4 segfault（P1，7 脚本，继承）

- 脚本：f031/f042/f043/f051/f056/f061/f072/f117/f178

### 5.5 测试文件未清理

工作区中存在 11 个临时测试文件：
```
test_3level.php, test_byref.php, test_cmp.php, test_concat.php,
test_f057_min.php, test_inarray.php, test_rec.php, test_rec2.php,
test_rec3.php, test_ref_arr.php, test_ternary.php
```

---

## 六、变更文件列表

| 文件 | 变更类型 | 说明 |
|------|----------|------|
| `src/aot/native_linker.zig` | 修改 | +153 行 / -13 行：foreach+break PHI 修复、for 回边修复、throw 终止符、辅助函数 |

### 核心变更明细

| 变更点 | 行号范围 | 说明 |
|--------|----------|------|
| `current_loop_cleanup_block` 字段 | ~245 | 新增字段跟踪 foreach cleanup 块 |
| `writeThrowTerminator` | ~522-551 | 新增 throw 终止符生成 |
| `isLoopBreakTarget` | ~565-572 | 新增循环退出目标检测 |
| `writeBrInLoopContext` | ~575-593 | 新增循环上下文中的 br 处理 |
| `generateExitPHIAssignments` | ~6644-6673 | 新增 PHI 赋值生成（核心） |
| `generateLoopConditionChain` | ~6021-6130 | 添加 `cleanup_idx` 参数 + 6 处 PHI 赋值 |
| `generateForeachFromLabels` | ~6800-6950 | 保存/恢复 cleanup_block + break 前生成 PHI |
| `generateForFromLabels` | ~7498-7530 | 回边检测 + cleanup_block 上下文 |
| `generateWhileFromLabels` | ~7987-8010 | cleanup_block 上下文 |
| `generateIfFromLabels` | ~8531-8533 | then 块添加 `.throw` case |
| 多处 `writeBrInLoopContext` 替换 | ~7011, 7059, 7689, 7737, 8177, 8226 | else 块 br 处理改用循环上下文感知版本 |

---

## 七、后续优化建议

| 优先级 | 影响面 | 落地成本 | 建议 |
|--------|--------|----------|------|
| **P0** | 1 脚本(f057) | 中 | 修复 if/else 合并点 PHI 消解：确保 `if_merge_` 块的指令在主循环 cond_br case 中完整生成，ternary PHI 正确消解 |
| **P0** | 17+ 脚本 | 中 | 修复 early-exit：不标记 `if_then_`/`logical_merge_`/`logical_rhs_` 为已处理（继承自 Session 12） |
| **P0** | 全局 | 低 | 编译验证 + 运行完整回归测试，确认本次 PHI 修复的效果和是否有回归 |
| P1 | 1 脚本(f080) | 中 | 修复 coalesce `??` PHI 消解：`??` 的隐式 if/else 合并点 PHI 未正确赋值 |
| P1 | 1 脚本(f070) | 中 | 修复 foreach null：对象数组属性初始化问题 |
| P1 | 5 脚本 | 中 | 修复 PHPString double free（release 后设置 alloca 为 null） |
| P1 | 17 脚本 | 高 | 排查 timeout 脚本（先修复 early-exit 可能解决部分） |
| P1 | 17 脚本 | 中 | 修复 FAIL_DIFF 输出差异 |
| P2 | 全局 | 低 | 清理 11 个临时测试文件 |
| P2 | 全局 | 高 | 为 `||`/`&&` 编写专用 `generateLogicalExpr` 函数，不依赖 cond_br case 或 `generateIfFromLabels` |

---

## 八、关键代码位置参考

| 功能 | 文件 | 行号范围 | 说明 |
|------|------|----------|------|
| `generateExitPHIAssignments` | native_linker.zig | ~6644-6673 | **新增**：break 前 PHI 赋值生成 |
| `current_loop_cleanup_block` | native_linker.zig | ~245 | **新增**：foreach cleanup 块跟踪 |
| `writeBrInLoopContext` | native_linker.zig | ~575-593 | **新增**：循环上下文 br 处理 |
| `isLoopBreakTarget` | native_linker.zig | ~565-572 | **新增**：循环退出目标检测 |
| `writeThrowTerminator` | native_linker.zig | ~522-551 | **新增**：throw 终止符生成 |
| `generateLoopConditionChain` | native_linker.zig | ~6021-6130 | **修改**：添加 cleanup_idx 参数 + 6 处 PHI 赋值 |
| `generateForeachFromLabels` | native_linker.zig | ~6800-6950 | **修改**：cleanup_block 上下文 + break 前生成 PHI |
| `generateForFromLabels` | native_linker.zig | ~7498-7530 | **修改**：回边检测优化 |
| `generateLabelDrivenBlockRange` | native_linker.zig | ~6046-6052 | early-exit（未修改，P0 待修复） |
| `generateLabelDrivenBlockRange` cond_br | native_linker.zig | ~6261-6500 | cond_br case（if/else 合并点 PHI 问题所在） |
| `generateIfFromLabels` | native_linker.zig | ~8400-8660 | if/else 结构化生成 |
| `.phi` case | native_linker.zig | ~15073-15078 | PHI 跳过（生成注释，不消解） |

---

## 九、调试用测试脚本说明

| 脚本 | 目的 | 关键发现 |
|------|------|----------|
| `test_f057_min.php` | 最小化 f057 工作流引擎 | AOT 仅遍历 3 节点，条件评估或递归调用有问题 |
| `test_rec.php` | 递归 + by-reference 参数 | ✅ 通过，排除了递归本身的问题 |
| `test_rec2.php` | 简化递归 | ✅ 通过 |
| `test_rec3.php` | by-ref + array_key_exists + ternary | ❌ AOT 输出不完整，初步定位问题 |
| `test_ternary.php` | 三元运算符 | ✅ 通过 |
| `test_ref_arr.php` | by-reference 数组修改 | ✅ 通过 |
| `test_concat.php` | 字符串拼接 | ✅ 通过 |
| `test_3level.php` | 3 层 by-ref 链 | ✅ 通过 |
| `test_inarray.php` | in_array + array_key_exists + ternary | ❌ **关键**：PHI `reg_44` 未赋值，json_encode 调用缺失 |

### `test_inarray.php` IR 结构关键发现

通过 `--dump-ir` 确认 `level2` 函数的 IR 块结构：

```
ternary_merge_2  →  br reg_14, if_then_3, if_merge_4
if_then_3        →  echo + ret
if_merge_4       →  json_encode + echo + array_key_exists + br reg_36, ternary_then_5, ternary_else_6
ternary_then_5   →  "yes" + box + br ternary_merge_7
ternary_else_6   →  "no" + box + br ternary_merge_7
ternary_merge_7  →  PHI reg_44 + concat + echo + ...
```

**核心问题**：`if_merge_4` 既是 `if ($found)` 的 merge 块，又包含后续代码（json_encode 等）和第二个 ternary 的 cond_br。代码生成器在处理这个"双重身份"块时出现错误：
1. `if_merge_4` 的指令（json_encode 等）没有在正确位置生成
2. `ternary_merge_7` 的 PHI `reg_44` 未被消解

**下一步修复方向**：
1. Dump `test_inarray.php` 的完整 Zig 代码，确认 `if_merge_4` 的指令是否被生成、在哪里生成
2. 检查 `generateLabelDrivenBlockRange` 主循环处理 `if_merge_4` 时 `cond_br` case 的 else 块处理逻辑
3. 确保 ternary 的 PHI 在 `generateIfFromLabels` 或 `cond_br` case 中被正确消解

---

## 十、注意事项

1. **本次修改尚未编译验证**：需要先执行 `timeout 120 zig build` 确认编译通过
2. **本次修改尚未运行回归测试**：需要执行 `bash scripts/regression_test_720.sh` 确认无回归
3. **临时测试文件需清理**：11 个 `test_*.php` 文件需要删除（注意不要删除 `.php` 原始脚本）
4. **AOT 编译产物需清理**：`/tmp/aot_*`、`aot_compile_test_*` 等临时产物需删除
5. **previous handover**：`docs/changes/2026-07-26/交接文档_2026-07-26_session12_完整交接.md` 中的 P0 early-exit 问题仍未修复，应优先处理
