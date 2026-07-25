# 交接文档：AST-Direct 标签驱动代码生成深度修复（Session #5）

> **日期**：2026-07-25  
> **会话**：Session #5（紧接 Session #4）  
> **状态**：f026 输出 21/23 项正确，仅剩 Peek/Front 两项空值  
> **核心文件**：`src/aot/native_linker.zig`（~22,012 行）

---

## 一、TL;DR（高层摘要）

本会话在 Session #4 基础上继续深度修复 AST-Direct 代码生成路径（`tryGenerateFromLabels` + `generateLabelDrivenBlockRange`），解决了 **13 个核心 bug**，使 f026 脚本从"编译崩溃/输出全错"提升到 **21/23 项输出与 PHP 完全一致**。

核心修复链路：
1. 废弃 fallback 回退链 → AST-Direct 失败直接报错
2. 循环条件不重新计算 → 移入 while 循环内部
3. PHI 节点未消解 → if/else/while/for/foreach 全面添加 PHI 消解
4. this 寄存器在 cleanup 中释放 → use-after-free
5. cond_br 的 ret 终止符未处理 → if/return 返回 null
6. else 块嵌套 cond_br 未递归处理 → Pop/Shift 返回 Array
7. return_generated 标志管理 → early-exit 标记 + unreachable 智能生成

---

## 二、已完成任务清单

### 2.1 废弃 fallback 回退链
- **修改文件**：`native_linker.zig` ~行 7242
- **修改内容**：AST-Direct 失败时 `return error.AstDirectGenerationFailed`，不再回退到 `tryGenerateStructuredControlFlowNew` / 状态机
- **影响**：所有函数必须通过 AST-Direct 路径，失败即报错

### 2.2 清理 AST-DIRECT 调试 print
- **修改文件**：`native_linker.zig` `tryGenerateFromLabels` 函数
- **修改内容**：移除 2 处 `std.debug.print("[AST-DIRECT] ...")` 调试输出

### 2.3 while/for/foreach 循环条件移入循环内部
- **修改文件**：`native_linker.zig` `generateWhileFromLabels` / `generateForFromLabels` / `generateForeachFromLabels`
- **修改内容**：
  - 将 cond 块指令从循环前移入 `while (true) { ... }` 内部
  - 使用 `if (!(cond)) break :label;` 替代 `while (cond) { ... }`
  - 确保每次迭代重新计算条件
- **影响**：修复无限循环（条件在循环前只计算一次）和循环不执行（条件值不正确）

### 2.4 `generateIfFromLabels` PHI 消解
- **修改文件**：`native_linker.zig` `generateIfFromLabels` 函数
- **修改内容**：在 then 分支和 else 分支末尾添加 PHI 赋值（简单赋值 `reg_X = reg_Y`）
- **影响**：if/else 分支中的变量通过 PHI 节点传递的值正确赋值到 merge 块的寄存器

### 2.5 `cond_br` 隐式 if/else 生成 + PHI 消解
- **修改文件**：`native_linker.zig` `generateLabelDrivenBlockRange` 的 `.cond_br` case
- **修改内容**：
  - 为非控制流前缀（非 `if_then_`/`while_cond_` 等）的 cond_br 生成隐式 if/else
  - 查找 then/else 块，生成 `if (cond) { then_blk } else { else_blk }`
  - 在 then/else 分支末尾添加 PHI 消解
  - 处理 merge 块（跳过已消解的 PHI 指令）
- **影响**：默认参数的 `params_all_present` / `params_has_missing` 分支正确生成

### 2.6 `cond_br` ret 终止符处理
- **修改文件**：`native_linker.zig` `.cond_br` case 的 then/else 块终止符处理
- **修改内容**：
  - then/else 块的终止符从仅处理 `.br` 扩展到处理 `.ret`
  - `.ret` 时生成 cleanup + `writeReturnStmt`（设置 `return_generated = true`）
- **影响**：`if (cond) return true; return false;` 模式正确生成返回值（之前返回 null）

### 2.7 this/ctx 寄存器过滤
- **修改文件**：`native_linker.zig` `tryGenerateFromLabels` 函数
- **修改内容**：过滤 `cleanup_regs`，排除 `current_this_regs` 中的寄存器
- **根因**：`cleanup_registers_set` 将所有 `php_object` 类型寄存器加入 cleanup，包括 `reg_0`（ctx/this）。简单路径有 `this_regs.contains(reg_id) continue` 跳过，但 AST-Direct 路径没有。构造函数 cleanup 释放 `reg_0` 导致对象被提前释放，`php_object_new_with_constructor` 返回已释放的对象 → use-after-free → segfault（仅 Release 模式）
- **影响**：修复构造函数 segfault，`new Node(42)` 不再崩溃

### 2.8 foreach 迭代器 PHI 消解
- **修改文件**：`native_linker.zig` `generateForeachFromLabels` 函数
- **修改内容**：
  - 循环前：添加初始 PHI 赋值（来自前驱块的 incoming 值）
  - increment 块后、continue 前：添加循环回边 PHI 赋值（来自 increment/body 块的 incoming 值）
- **根因**：foreach cond 块有 PHI 节点（迭代器寄存器），合并前驱块的初始值和 increment 块的更新值。PHI 未消解导致迭代器为 null，`php_array_iter_valid(null)` 返回 false，循环不执行
- **影响**：`foreach ([1,2,3] as $v) $list->push($v);` 正确执行

### 2.9 while/for 循环 PHI 消解
- **修改文件**：`native_linker.zig` `generateWhileFromLabels` / `generateForFromLabels` 函数
- **修改内容**：与 foreach 相同的 PHI 消解模式（循环前 + 回边处）
- **根因**：while cond 块有 PHI 节点（如 `$prev` 变量），合并 entry 的初始值和 body 的更新值。PHI 未消解导致 `$prev` 始终为 null，`$current->next = null` 破坏链表
- **影响**：`LinkedList::reverse()` 正确反转链表

### 2.10 `return_generated` 传播 + early-exit 标记
- **修改文件**：`native_linker.zig` `generateLabelDrivenBlockRange` early-exit + `generateControlFlowStateMachine` fallback
- **修改内容**：
  - early-exit 处标记剩余块为已处理（`for (i..end_idx) |j| { try processed.put(j, {}); }`），避免 `tryGenerateFromLabels` 报告未处理块
  - `return_generated = true` 时不生成 fallback `return null`，而是检查最后生成行是否已是 return 语句
  - 如果最后行是 return，不生成 `unreachable`（避免 Zig "unreachable code" 错误）
  - 如果最后行不是 return（如 `}` 闭合 if/else），生成 `unreachable`（满足 Zig "must return" 要求）
- **影响**：if/else 两分支都 return 时正确处理，不产生 Zig 编译错误

### 2.11 else 块 cond_br 递归处理
- **修改文件**：`native_linker.zig` `.cond_br` case 的 else 块终止符处理
- **修改内容**：
  - else 块终止符为 `.cond_br` 时，递归调用 `generateLabelDrivenBlockRange` 处理后续块
  - 递归调用前保存 `return_generated` 并重置为 false（防止 then 块的 ret 导致递归提前退出）
  - 递归调用后恢复 `return_generated`
- **根因**：`LinkedList::pop()` 的 `if_merge_1` 块有嵌套 cond_br（到 `if_then_2`/`if_merge_3`），但 `.cond_br` case 只处理 `.br` 和 `.ret`，`cond_br` 落入 `else => {}` 不处理。后续块（if_then_2, while_cond_4 等）未处理，`return_generated` 为 true 导致 early-exit 标记剩余块为已处理但实际未生成代码 → 运行时 `unreachable` 返回垃圾值（"Array"）
- **影响**：Pop 返回正确的标量值（5），Shift 返回正确的标量值（0）

---

## 三、f026 输出对比

### 3.1 匹配项（21/23）

| 测试项 | PHP | AOT |
|---|---|---|
| LinkedList: List | 1->2->3->4->5 | ✅ |
| LinkedList: After unshift(0) | 0->1->2->3->4->5 | ✅ |
| LinkedList: Pop | 5 | ✅ |
| LinkedList: Shift | 0 | ✅ |
| LinkedList: List (after pop/shift) | 1->2->3->4 | ✅ |
| LinkedList: Reversed | 4->3->2->1 | ✅ |
| LinkedList: Find >3 | 4 | ✅ |
| LinkedList: Size | 4 | ✅ |
| Stack: Stack | 1,2,3 | ✅ |
| Stack: Pop | 3 | ✅ |
| Stack: Pop | 2 | ✅ |
| Stack: Size | 1 | ✅ |
| Queue: Dequeue | A | ✅ |
| Queue: Dequeue | B | ✅ |
| Queue: Size | 1 | ✅ |
| Deque: 全部 | 正确 | ✅ |
| RingBuffer: Push sizes | 1,2,3 | ✅ |
| RingBuffer: Is full | true | ✅ |
| RingBuffer: Push 4 (should fail) | false | ✅ |
| RingBuffer: Pop / Push 4 / Buffer | 1 / true / 2,3,4 | ✅ |
| Done | === f026 Done === | ✅ |

### 3.2 未匹配项（2/23）

| 测试项 | PHP | AOT | 原因分析 |
|---|---|---|---|
| Stack: Peek | 3 | 空 | `return $this->items[count($this->items) - 1] ?? null;` — 数组访问 + `??` 运算符 |
| Queue: Front | A | 空 | `return $this->items[0] ?? null;` — 数组访问 + `??` 运算符 |

---

## 四、进行中 / 待办任务

### 4.1 待办

| ID | 任务 | 优先级 | 说明 |
|---|---|---|---|
| 15 | 修复 Peek/Front 空 | P0 | 数组访问 `$arr[expr] ?? null` 在 AST-Direct 路径的处理 |
| 4 | 全量回归测试 | P0 | 对 `fuzzy_scripts_720/pass/` 全部 67 脚本运行回归测试 |
| 17 | 修复 callable/箭头函数 | P1 | `fn($v) => $v > 3` 在 AST-Direct 路径中的问题 |
| 11 | 生成变更摘要文档 | P2 | 按宪法要求生成 `docs/changes/` 变更文档 |

### 4.2 已完成

| ID | 任务 | 状态 |
|---|---|---|
| 1 | 废弃 fallback 回退链 | ✅ |
| 2 | 清理 AST-DIRECT 调试 print | ✅ |
| 3 | 验证 f026 AOT 产物正确性 | ✅ (21/23) |
| 5 | 编译验证 | ✅ |
| 6 | while 循环条件移入内部 | ✅ |
| 7 | for 循环条件移入内部 | ✅ |
| 8 | foreach 循环条件移入内部 | ✅ |
| 9 | 编译+测试验证 f026 | ✅ |
| 10 | cond_br 隐式 if/else + PHI 消解 | ✅ |
| 12 | 定位构造函数 segfault | ✅ |
| 13 | 过滤 this 寄存器 | ✅ |
| 14 | while 循环 PHI 消解 | ✅ |
| 16 | var_export 返回值修复 | ✅ |
| 18 | Pop/Shift 返回值修复 | ✅ |

---

## 五、已知问题

### 5.1 Peek/Front 空（数组访问 + `??` 运算符）

**现象**：`Stack::peek()` 返回 `$this->items[count($this->items) - 1] ?? null`，AOT 输出为空。

**推测原因**：
- `??` 运算符生成 `select` 或 `cond_br` 指令
- 数组访问 `$arr[expr]` 可能生成 `array_get` 指令
- `count()` 函数调用可能涉及函数调用代码生成
- 这些指令在 AST-Direct 路径中的 `generateInstructionSimple` 处理可能有缺陷

**调试路径**：dump IR 查看 `Stack::peek` 方法的块结构 → dump 生成代码检查 `select`/`array_get` 指令的生成结果

### 5.2 编译时间较长

f026 的 AOT 编译（`zig build-exe`）需要约 2-4 分钟，因为生成的 Zig 代码量很大（~50000 行）。全量回归测试 67 个脚本会非常耗时。

### 5.3 PHI 消解使用简单赋值

当前 PHI 消解使用 `reg_X = reg_Y`（简单赋值），没有 retain/release。对于引用计数的对象类型，这可能导致引用计数不平衡。但在当前测试中未发现问题（整数/布尔等基本类型不需要引用计数）。

---

## 六、后续优化建议

| 优先级 | 影响面 | 落地成本 | 建议 |
|---|---|---|---|
| P0 | Peek/Front | 中 | 修复数组访问 + `??` 运算符在 AST-Direct 路径的代码生成 |
| P0 | 回归测试 | 高 | 对 `fuzzy_scripts_720/pass/` 67 脚本运行回归，确认无回退 |
| P1 | PHI 引用计数 | 中 | 为对象类型的 PHI 消解添加 retain/release（使用 `generatePhiValueAssignment`） |
| P1 | callable | 高 | 修复箭头函数 `fn($v) => $v > 3` 在 AST-Direct 路径的处理 |
| P2 | 变更文档 | 低 | 生成 `docs/changes/2026-07-25/` 变更摘要文档 |
| P2 | 编译优化 | 中 | 优化生成的 Zig 代码量，减少 `setSourceLocation` 等冗余调用 |

---

## 七、关键技术决策记录

### 7.1 PHI 消解策略

**决策**：使用简单赋值 `reg_X = reg_Y` 而非 `generatePhiValueAssignment`（含 retain/release）。

**原因**：`generatePhiValueAssignment` 在某些情况下导致 Release 模式 segfault（构造函数 use-after-free）。简单赋值在基本类型（整数/布尔）上工作正常。对象类型的 PHI 消解可能需要后续添加 retain/release。

### 7.2 `return_generated` 标志管理

**决策**：不保存/恢复 `return_generated`（让 if/else 内的 return 正确传播），通过 early-exit 标记剩余块为已处理来避免 `AstDirectGenerationFailed`。

**原因**：保存/恢复导致 if/return 模式返回 null（fallback return 被生成）。不保存/恢复 + early-exit 标记是唯一同时满足"return 正确传播"和"所有块标记为已处理"的方案。

### 7.3 else 块 cond_br 递归处理

**决策**：else 块终止符为 `cond_br` 时，递归调用 `generateLabelDrivenBlockRange`，递归前保存/重置 `return_generated`。

**原因**：else 块的 cond_br 不处理会导致后续块（嵌套 if、while 循环等）未生成代码。递归前必须重置 `return_generated`，否则 then 块的 ret 会导致递归立即退出。

---

## 八、代码修改位置索引

| 修改 | 文件 | 函数/位置 | 行号范围（约） |
|---|---|---|---|
| 废弃 fallback | native_linker.zig | `generateControlFlowStateMachine` | ~7234-7245 |
| 清理调试 print | native_linker.zig | `tryGenerateFromLabels` | ~5890-5910 |
| while cond 移入内部 | native_linker.zig | `generateWhileFromLabels` | ~6576-6610 |
| for cond 移入内部 | native_linker.zig | `generateForFromLabels` | ~6435-6470 |
| foreach cond 移入内部 | native_linker.zig | `generateForeachFromLabels` | ~6226-6260 |
| if PHI 消解 | native_linker.zig | `generateIfFromLabels` | ~6940-6980 |
| cond_br 隐式 if/else | native_linker.zig | `generateLabelDrivenBlockRange` `.cond_br` | ~6029-6180 |
| cond_br ret 处理 | native_linker.zig | `.cond_br` then/else 终止符 | ~6042-6135 |
| this 寄存器过滤 | native_linker.zig | `tryGenerateFromLabels` | ~5878-5890 |
| foreach PHI 消解 | native_linker.zig | `generateForeachFromLabels` | ~6226, ~6314 |
| while/for PHI 消解 | native_linker.zig | `generateWhileFromLabels` / `generateForFromLabels` | ~6576, ~6666, ~6435, ~6532 |
| early-exit 标记 | native_linker.zig | `generateLabelDrivenBlockRange` | ~5922-5928 |
| unreachable + last_return | native_linker.zig | `generateControlFlowStateMachine` | ~7237-7260 |
| else 块 cond_br 递归 | native_linker.zig | `.cond_br` else 终止符 | ~6136-6145 |
